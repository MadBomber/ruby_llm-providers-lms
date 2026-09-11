# ruby_llm-providers-lms

[RubyLLM](https://rubyllm.com) provider gem for [LM Studio](https://lmstudio.ai) — run
local models through LM Studio's OpenAI-compatible server (`lms server start`,
`http://localhost:1234/v1` by default).

The provider works out of the box: no API key, no configuration. It speaks the
Chat Completions dialect by default, registers the Responses protocol
(LM Studio serves `/v1/responses` too), and adds a `:native_chat` protocol for
LM Studio's own stateful REST API — server-stored conversations, reasoning
control, server-side MCP tools, and performance stats (see "The native chat
protocol"). Model listings are enriched with details from LM Studio's native
REST API (`/api/v0/models`): architecture, quantization, load state, context
length, and tool/vision capabilities. Model-management helpers load, unload,
and download models through `/api/v1/models`.

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
| Native REST v1 | `POST /api/v1/chat`, `GET /api/v1/models`, `POST /api/v1/models/load`, `POST /api/v1/models/unload`, `POST /api/v1/models/download` | the `:native_chat` protocol and model management (see below) |

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

LM Studio also accepts request fields on the OpenAI-compatible endpoints
that are not part of OpenAI's vocabulary. RubyLLM merges
`with_provider_options` into the request payload as-is, so all of these
work today (the native chat protocol below rejects unknown keys — these
belong to the OpenAI-compatible surface):

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

## The native chat protocol

LM Studio's native REST API (`POST /api/v1/chat`) offers capabilities the
OpenAI-compatible surface cannot express. Select it per chat with
`protocol: :native_chat` (or globally with
`config.lms_protocol = :native_chat`):

```ruby
chat = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms,
                    protocol: :native_chat, assume_model_exists: true)
response = chat.ask('Hello')
```

What it adds over the default Chat Completions protocol:

- **Stateful conversations** — LM Studio stores each response server-side
  and continues from a `response_id` instead of replaying history. Ordinary
  RubyLLM multi-turn chats just work: each request sends only the new
  messages and points `previous_response_id` at the last stored response.
  The id is on `response.raw.body['response_id']`.
- **Performance stats** — `response.raw.body['stats']` carries tokens per
  second, time to first token, and token counts; `response.tokens` (input,
  output, thinking) is filled from it.
- **Reasoning control** — `chat.with_thinking(effort: :low)` maps onto the
  native `reasoning` setting (`off` / `low` / `medium` / `high` / `on`;
  models accept a subset — gpt-oss takes efforts, most others just on/off).
  Reasoning output comes back separated as `response.thinking.text`,
  streamed as thinking chunks.
- **Server-side MCP tools** — pass
  `with_provider_options(integrations: [...])` to have the server itself run
  MCP plugins from `mcp.json` (`{ id: 'mcp/playwright' }`) or ephemeral MCP
  servers declared in the request (`server_label` / `server_url`), with
  optional `allowed_tools` filtering. Executed tool calls appear in
  `response.raw.body['output']`.
- **Per-request context length** — `with_provider_options(context_length: 8192)`.
- **Opting out of storage** — `with_provider_options(store: false)` keeps the
  conversation off the server, at the cost of multi-turn continuity.

Limitations: the native API runs no client-side tools (RubyLLM `with_tools`
raises — use `:chat_completions`, or MCP integrations), has no structured
output (`with_schema` raises), and takes image input only (as `data_url`
parts). Unknown request keys are rejected by the server, so the
OpenAI-endpoint extras (`ttl`, `draft_model`, ...) don't apply here.

## Model management

The provider exposes LM Studio's native model-management endpoints, so you
can control what is in memory without shelling out to `lms`:

```ruby
provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)

provider.native_models   # every downloaded model, with architecture,
                         # quantization, capabilities, loaded_instances, ...
provider.loaded_models   # just the ones resident in memory

instance = provider.load_model('qwen/qwen3-4b', context_length: 8192)
# => { "instance_id" => "qwen/qwen3-4b", "status" => "loaded", ... }
provider.unload_model(instance['instance_id'])

provider.download_model('qwen/qwen3-4b')  # fetch a new model onto disk
```

`load_model` returns the `instance_id` that `unload_model` takes; loading a
model that is already resident starts a second instance (`...:2`), so hold
on to the id you were given. Note that `ttl` is not a load option on the
native API — set idle TTL per request through the OpenAI-compatible
endpoints (see "LM Studio extras") or `lms load --ttl`.

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
(chat, tools, structured output, embeddings, native chat — where the
reasoning matrix needs a model that emits reasoning items, such as gpt-oss).
The portable contract specs are
adapted from [RubyLLM's live specs](https://github.com/crmne/ruby_llm/tree/main/spec/ruby_llm).
