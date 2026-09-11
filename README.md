# ruby_llm-providers-lms

[RubyLLM](https://rubyllm.com) provider gem for [LM Studio](https://lmstudio.ai) — run
local models through LM Studio's OpenAI-compatible server (`lms server start`,
`http://localhost:1234/v1` by default).

The provider works out of the box: no API key, no configuration. It speaks the
Chat Completions dialect by default and also registers the Responses protocol
(LM Studio serves `/v1/responses` too). Model listings are enriched with details
from LM Studio's native REST API (`/api/v0/models`): architecture, quantization,
load state, context length, and tool/vision capabilities.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ruby_llm-providers-lms', require: 'ruby_llm/providers/lms'
```

Configuration is optional. Override the defaults only when your server is not
on `http://localhost:1234/v1` or sits behind an auth proxy:

```ruby
require 'ruby_llm/providers/lms'

RubyLLM.configure do |config|
  config.lms_api_base = ENV.fetch('LMS_API_BASE', 'http://localhost:1234/v1')
  config.lms_api_key = ENV['LMS_API_KEY'] # only if your server requires auth
end
```

## Usage

Use the model identifier shown in LM Studio (not an OpenAI model name):

```ruby
chat = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms)
response = chat.ask('Hello')
puts response.content
```

If the server isn't running, requests raise a `RubyLLM::Error` telling you to
start it (`lms server start`) instead of a raw connection failure.

Because LM Studio is a local provider, RubyLLM assumes any model id you pass
exists — LM Studio will just-in-time load the model if it isn't loaded yet.
To browse what the server offers right now, ask the provider directly:

```ruby
provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)
provider.list_models.each { |model| puts model.id }
```

## The model catalog (models.json)

The gem ships a `models.json` at its root. **This file is only a sample**,
recorded from the author's machine: LM Studio serves whatever models *you*
have downloaded, so your catalog will be different. RubyLLM loads the shipped
file as the provider's model registry so `RubyLLM.models` has something to
show.

Note that `RubyLLM.models.refresh` does **not** query your LM Studio server:
provider gems that ship a registry file are excluded from the live fetch, and
refresh just re-reads the registered `models.json`. Your live server is still
the source of truth, reached differently depending on what you need:

- **Chatting** needs no catalog at all — any model id LM Studio knows will
  work (see above).
- **Browsing what your server offers** is `provider.list_models` (see the
  snippet above), which hits the live endpoints every time.
- **Making `RubyLLM.models` reflect your machine** means registering your own
  catalog file in place of the shipped sample:

  ```ruby
  require 'ruby_llm/providers/lms'

  provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)
  RubyLLM::Models.new(provider.list_models).save_to_json('my_models.json')
  RubyLLM::Provider.register :lms, RubyLLM::Providers::LMS, models: 'my_models.json'
  RubyLLM.models.refresh
  ```

Don't edit the `models.json` inside the installed gem — it is overwritten on
every gem update; re-register with your own file instead.

Embeddings work the same way:

```ruby
RubyLLM.embed('Hello world', model: 'text-embedding-nomic-embed-text-v1.5', provider: :lms)
```

To use the Responses dialect instead of Chat Completions:

```ruby
RubyLLM.configure { |config| config.lms_protocol = :responses }
```

## LM Studio server options

LM Studio serves three API surfaces on one port (`http://localhost:1234` by
default). This gem talks to the first two:

| Surface | Endpoints | Used by this gem |
| --- | --- | --- |
| OpenAI-compatible | `GET /v1/models`, `POST /v1/chat/completions`, `POST /v1/completions`, `POST /v1/embeddings`, `POST /v1/responses` | chat, tools, structured output, embeddings, Responses protocol |
| Native REST v0 | `GET /api/v0/models`, `GET /api/v0/models/{model}`, `POST /api/v0/chat/completions`, `POST /api/v0/completions`, `POST /api/v0/embeddings` | model-listing enrichment |
| Native REST v1 | `POST /api/v1/chat`, `GET /api/v1/list`, `POST /api/v1/load`, `POST /api/v1/unload`, `POST /api/v1/download`, `GET /api/v1/download-status` | not yet (see below) |

### Standard request parameters

On its OpenAI-compatible chat endpoints LM Studio honors the usual OpenAI
vocabulary: `model`, `messages`, `temperature`, `top_p`, `max_tokens`,
`stream`, `stop`, `presence_penalty`, `frequency_penalty`, `logit_bias`,
`seed`, `tools` / `tool_choice`, and `response_format` with a `json_schema`
(strict structured output). Vision models accept image content parts. You
reach all of these through RubyLLM's normal API — `with_temperature`,
`with_max_output_tokens`, `with_tools`, `with_schema`, `chat.ask(with: 'image.png')`,
and so on; nothing LM Studio-specific is required.

### LM Studio extras

LM Studio also accepts request fields that are not part of OpenAI's
vocabulary. RubyLLM merges `with_provider_options` into the request payload
as-is, so all of these work today:

| Option | What it does |
| --- | --- |
| `ttl` | Idle time-to-live in seconds for the model handling this request. A JIT-loaded model unloads itself after sitting idle that long (LM Studio's default is 60 minutes; each request resets the timer). |
| `draft_model` | Enables speculative decoding: a small draft model proposes tokens the main model verifies, often speeding up generation substantially. Both models must use the same tokenizer family. |
| `top_k` | Sample only from the k most likely tokens. |
| `min_p` | Discard tokens below this base probability. |
| `repeat_penalty` | Penalize recently generated tokens to discourage repetition. |

```ruby
chat = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms)
chat.with_provider_options(
  ttl: 300,                        # unload after 5 idle minutes
  draft_model: 'qwen/qwen3-0.6b',  # speculative decoding
  top_k: 40,
  min_p: 0.05,
  repeat_penalty: 1.1
)
chat.ask('Hello')
```

### Model lifecycle: JIT loading, TTL, auto-evict

Because LM Studio only serves models you have downloaded, the server manages
memory rather than a fleet:

- **JIT loading** — with just-in-time loading enabled (the server default),
  `/v1/models` lists every downloaded model and an inference request for an
  unloaded model loads it on demand. Expect a long time-to-first-token on
  that first request. With JIT off, only already-loaded models are served.
- **TTL** — JIT-loaded models default to a 60-minute idle TTL; override it
  per request with the `ttl` option above, or at load time with
  `lms load <model> --ttl 3600`. Models loaded explicitly via `lms load`
  have no TTL and stay resident until unloaded.
- **Auto-evict** — by default LM Studio keeps at most one JIT-loaded model
  in memory, evicting the previous one before loading the next. Turn
  auto-evict off in the server settings to keep several models resident at
  once (each still subject to its own TTL).

The `state` field in this gem's model metadata (`loaded` / `not-loaded`)
comes from the native v0 API and tells you which models are resident right
now.

### Native REST APIs (not yet wired up)

The native APIs offer capabilities the OpenAI-compatible surface cannot
express. This gem does not use them yet, beyond the v0 model-listing
enrichment:

- **Performance stats** — native v0/v1 chat responses include a `stats`
  object (tokens per second, time to first token, generation time, and
  draft-token acceptance counts when speculative decoding is active) plus
  `model_info` and `runtime` blocks.
- **Stateful chats** — `/api/v1/chat` stores conversations server-side
  (`store`, default true) and continues them via `previous_response_id`.
- **Reasoning control** — `/api/v1/chat` takes a `reasoning` effort option
  (`off` / `low` / `medium` / `high` / `on`) and returns reasoning output as
  separate items.
- **Server-side MCP tools** — `/api/v1/chat` can run tools itself through
  `integrations`: pre-configured MCP plugins from `mcp.json` or ephemeral
  MCP servers declared in the request, with `allowed_tools` filtering.
- **Per-request context length** — `/api/v1/chat` accepts a
  `context_length` override.
- **Model management** — `/api/v1/load`, `/api/v1/unload`, `/api/v1/download`,
  and `/api/v1/download-status` control what is in memory and on disk.

## Development

Start the LM Studio server (`lms server start`), then:

```sh
bundle exec rake models   # refresh models.json from your local server
bundle exec rake          # rubocop, flay, archspec, specs
```

`rake models` calls the local server's model-listing endpoints and rewrites
the sample `models.json` at the gem root (see "The model catalog" above) —
it is a maintainer task for refreshing the shipped sample, not something gem
users run.

The suite always runs the provider integration specs. The first local run
calls the API and records VCR cassettes; CI only replays committed cassettes.
A failing example deletes its cassette so the next local run tests the live
API again.

After refreshing the catalog, put real model IDs from your machine into
`spec/support/models.rb`. Keep only the operation matrices LM Studio supports
(chat, tools, structured output, embeddings). The portable contract specs are
adapted from [RubyLLM's live specs](https://github.com/crmne/ruby_llm/tree/main/spec/ruby_llm).
