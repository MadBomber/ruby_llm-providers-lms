# ruby_llm-providers-lms

[RubyLLM](https://rubyllm.com) provider gem for [LM Studio](https://lmstudio.ai) — run
local models through LM Studio's local server (`lms server start`,
`http://localhost:1234/v1` by default).

LM Studio speaks three APIs on one port, and this gem covers all three: the
**OpenAI** API (the default, and the most capable here), the **Anthropic**
Messages API, and LM Studio's own **native REST** API — which adds inference
stats, server-stored conversations, and model management. The provider works
out of the box: no API key, no configuration.

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

## Quick start

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

---

# The three APIs

| API | Endpoints | Protocols |
| --- | --- | --- |
| [OpenAI](#the-openai-api) | `POST /v1/chat/completions`, `POST /v1/responses`, `GET /v1/models`, `POST /v1/embeddings`, `POST /v1/completions` | `:chat_completions` (default), `:responses` |
| [Anthropic](#the-anthropic-api) | `POST /v1/messages` | `:anthropic` |
| [Native REST](#the-native-rest-api) | v0: `POST /api/v0/chat/completions`, `GET /api/v0/models`, `POST /api/v0/embeddings`, … <br> v1: `POST /api/v1/chat`, `GET /api/v1/models`, `POST /api/v1/models/load`, `/unload`, `/download` | `:native_v0`, `:native_chat` |

Everything but the default is opt-in. Pick a protocol process-wide, for one
conversation, or for a single chat:

```ruby
RubyLLM.configure { |config| config.lms_protocol = :anthropic }      # process-wide

RubyLLM.context { |config| config.lms_protocol = :native_v0 }        # one conversation
       .chat(model: 'qwen/qwen3-4b', provider: :lms)

RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms,                 # one chat
             protocol: :native_chat, assume_model_exists: true)
```

## Which protocol should you use?

Stay on the default unless you need something only another column offers.

| | `:chat_completions` | `:responses` | `:anthropic` | `:native_v0` | `:native_chat` |
| --- | --- | --- | --- | --- | --- |
| Streaming | yes | yes | yes | yes | yes |
| Client-side tools (`with_tools`) | yes | yes | yes | yes | **no** — raises; use MCP integrations |
| Structured output (`with_schema`) | yes | **ignored, silently** | **ignored, silently** | yes | **no** — raises |
| Inference stats | no | no | no | yes, via `raw` | yes, via `tokens` |
| LM Studio request extras | yes | yes | yes | yes | **no** — server rejects them |
| Server-stored conversations | no | no | no | no | yes |
| Reasoning control | no | no | no | no | yes |

Checked against LM Studio 0.4.24+1 (see [Tested against](#tested-against)).
Where a protocol ignores something silently rather than raising, the section
below says so — those are the cases that cost you an afternoon.

---

# The OpenAI API

The surface most code already targets, and the one with the fewest surprises
here: everything RubyLLM can express works.

## Chat Completions — `:chat_completions`

The default protocol; nothing to configure. LM Studio honors the usual OpenAI
vocabulary on `POST /v1/chat/completions`: `model`, `messages`, `temperature`,
`top_p`, `max_tokens`, `stream`, `stop`, `presence_penalty`,
`frequency_penalty`, `logit_bias`, `seed`, `tools` / `tool_choice`, and
`response_format` with a `json_schema` (strict structured output). Vision
models accept image content parts.

You reach all of it through RubyLLM's normal API — `with_temperature`,
`with_max_output_tokens`, `with_tools`, `with_schema`,
`chat.ask(with: 'image.png')` — nothing LM Studio-specific required.

## Responses — `:responses`

LM Studio also serves OpenAI's newer Responses API at `POST /v1/responses`,
and RubyLLM's stock Responses protocol drives it:

```ruby
RubyLLM.configure { |config| config.lms_protocol = :responses }
```

Streaming and client-side tools work. **`with_schema` does not** — LM Studio
ignores the schema on this endpoint and nothing raises, so you get
unconstrained prose where you expected JSON. Use `:chat_completions` for
structured output.

## Embeddings

Embeddings go to `POST /v1/embeddings` regardless of which chat protocol is
in effect:

```ruby
RubyLLM.embed('Hello world', model: 'text-embedding-nomic-embed-text-v1.5', provider: :lms)
```

## LM Studio request extras

LM Studio accepts request fields that are not part of OpenAI's vocabulary.
RubyLLM merges `with_provider_options` into the payload as-is, so these work
on every protocol except `:native_chat`, whose server rejects unknown keys:

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

---

# The Anthropic API

LM Studio serves Anthropic's Messages API at `POST /v1/messages`, so a
codebase written against Claude can point at a local model without changing
how it talks:

```ruby
RubyLLM.configure { |config| config.lms_protocol = :anthropic }

chat = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms)
chat.ask('Hello').raw.body
# => {"id" => "msg_...", "type" => "message", "role" => "assistant",
#     "content" => [{"type" => "text", "text" => "..."}],
#     "stop_reason" => "end_turn",
#     "usage" => {"input_tokens" => 18, "output_tokens" => 25, ...}}
```

RubyLLM's stock Anthropic protocol drives it unchanged apart from the request
path. LM Studio wants no credentials and no `anthropic-version` header.

Plain exchanges, streaming (proper `message_start` / `content_block_delta`
SSE events) and tool calls (`tool_use` blocks with `stop_reason: "tool_use"`,
executed as ordinary `RubyLLM::Tool` objects in your process) all work; the
live specs in `spec/ruby_llm/chat_anthropic_spec.rb` cover all three.

**`with_schema` does not work here, and fails quietly.** LM Studio ignores the
schema and nothing raises. The same model and schema, two protocols:

```ruby
# :chat_completions => {"name": "John", "age": 30}
# :anthropic        => "Understood. John is 30 years old. How can I help..."
```

Use `:chat_completions` for structured output.

---

# The native REST API

LM Studio's own API, in two generations. **v0** mirrors the OpenAI shapes and
adds telemetry; **v1** is a different design, with server-stored conversations
and model management. The gem uses both.

One path gotcha: model management lives under `/api/v1/models/`, not directly
under `/api/v1/` — it is `POST /api/v1/models/load`, not `POST /api/v1/load`.
On 0.4.24+1 there is no `download-status` endpoint under either spelling.

## Inference stats — `:native_v0`

`POST /api/v0/chat/completions` is a strict superset of
`/v1/chat/completions`: the same request — streaming, `with_tools`,
`with_schema` and the request extras all included — and the same `choices`
and `usage`, but it fills in the `stats` block that the OpenAI endpoint
returns empty, and adds `model_info` and `runtime`.

```ruby
RubyLLM.configure { |config| config.lms_protocol = :native_v0 }

response = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms).ask('Hello')
response.raw.body['stats']
# => {"tokens_per_second" => 115.19, "time_to_first_token" => 0.0157,
#     "generation_time" => 0.172, "stop_reason" => "eosFound"}
response.raw.body['runtime']['name']  # => "llama.cpp-mac-arm64-apple-metal-advsimd"
```

RubyLLM has no field for any of this, so it arrives through `Message#raw` —
unlike `:native_chat`, which folds its stats into `response.tokens`.
Everything else behaves identically: this is the default protocol pointed at a
different URL. Reach for it when you want telemetry **and** the full Chat
Completions feature set.

`/v1/chat/completions` does return a `stats` key of its own, but it is `{}` on
an ordinary request; it carries only `total_draft_tokens_count` and its
accepted/rejected counterparts, and only when the model was loaded with a
`draft_model` for speculative decoding. The timing figures, `model_info` and
`runtime` are v0-only.

## Stateful chat — `:native_chat`

`POST /api/v1/chat` offers capabilities the OpenAI surface cannot express:

```ruby
chat = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms,
                    protocol: :native_chat, assume_model_exists: true)
response = chat.ask('Hello')
```

- **Stateful conversations** — LM Studio stores each response server-side and
  continues from a `response_id` instead of replaying history. Ordinary
  RubyLLM multi-turn chats just work: each request sends only the new messages
  and points `previous_response_id` at the last stored response. The id is on
  `response.raw.body['response_id']`.
- **Performance stats** — `response.raw.body['stats']` carries tokens per
  second, time to first token, and token counts; `response.tokens` (input,
  output, thinking) is filled from it.
- **Reasoning control** — `chat.with_thinking(effort: :low)` maps onto the
  native `reasoning` setting (`off` / `low` / `medium` / `high` / `on`; models
  accept a subset — gpt-oss takes efforts, most others just on/off). Reasoning
  output comes back separated as `response.thinking.text`, streamed as
  thinking chunks.
- **Server-side MCP tools** — pass `with_provider_options(integrations: [...])`
  to have the server itself run MCP plugins from `mcp.json`
  (`{ id: 'mcp/playwright' }`) or ephemeral MCP servers declared in the
  request (`server_label` / `server_url`), with optional `allowed_tools`
  filtering. Executed tool calls appear in `response.raw.body['output']`.
- **Per-request context length** — `with_provider_options(context_length: 8192)`.
- **Opting out of storage** — `with_provider_options(store: false)` keeps the
  conversation off the server, at the cost of multi-turn continuity.

Limitations: no client-side tools (`with_tools` raises — use
`:chat_completions`, or MCP integrations), no structured output
(`with_schema` raises), and image input only as `data_url` parts. Unknown
request keys are rejected, so the LM Studio request extras (`ttl`,
`draft_model`, …) don't apply here.

## Model management

The provider exposes LM Studio's native model-management endpoints, so you can
control what is in memory without shelling out to `lms`:

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
model that is already resident starts a second instance (`...:2`), so hold on
to the id you were given. Note that `ttl` is not a load option on the native
API — set idle TTL per request through the OpenAI endpoints (see
[LM Studio request extras](#lm-studio-request-extras)) or `lms load --ttl`.

---

# Models on your machine

## What listing enrichment adds

`provider.list_models` starts from the OpenAI-compatible `/v1/models` listing,
which carries little beyond an id, and merges in LM Studio's native model
listing. It tries `GET /api/v1/models` first and falls back to
`GET /api/v0/models`; when neither answers — an older build, or the native API
turned off — the plain listing is still returned.

`Model#name` becomes the human-readable display name where one is reported
(`"Qwen3 27B"` rather than `"qwen/qwen3.8-27b"`), and `Model#metadata` picks
up whatever the server knows:

| Key | From | Example |
| --- | --- | --- |
| `publisher`, `arch`, `quantization`, `compatibility_type`, `state` | v0 and v1 | `"qwen"`, `"qwen35"`, `"Q4_K_M"`, `"gguf"`, `"loaded"` |
| `display_name` | v1 | `"Qwen3 27B"` |
| `params_string` | v1 | `"27B"` |
| `size_bytes` | v1 | `17742039110` |
| `reasoning_options` | v1 | `["off", "low", "medium", "xhigh", "on"]` |
| `loaded_context_length` | v1 | `8192` (the loaded instance's window, which can be smaller than `context_window`) |

## The packaged catalog (models.json)

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
  work.
- **Browsing what your server offers** is `provider.list_models`, which hits
  the live endpoints every time.
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

## Model lifecycle: JIT loading, TTL, auto-evict

Because LM Studio only serves models you have downloaded, the server manages
memory rather than a fleet:

- **JIT loading** — with just-in-time loading enabled (the server default),
  `/v1/models` lists every downloaded model and an inference request for an
  unloaded model loads it on demand. Expect a long time-to-first-token on that
  first request. With JIT off, only already-loaded models are served.
- **TTL** — JIT-loaded models default to a 60-minute idle TTL; override it per
  request with the `ttl` option, or at load time with
  `lms load <model> --ttl 3600`. Models loaded explicitly via `lms load` have
  no TTL and stay resident until unloaded.
- **Auto-evict** — by default LM Studio keeps at most one JIT-loaded model in
  memory, evicting the previous one before loading the next. Turn auto-evict
  off in the server settings to keep several models resident at once (each
  still subject to its own TTL).

The `state` field in model metadata (`loaded` / `not-loaded`) tells you which
models are resident right now.

---

# Development

## Tested against

| Component | Version |
| --- | --- |
| LM Studio (macOS) | 0.4.24+1 |
| `lms` CLI | commit `ff50809` |
| RubyLLM | 2.0.0.rc3 |

This is the server the committed VCR cassettes were recorded from, and the
version every endpoint and capability claim above was checked against. LM
Studio's OpenAI-compatible surface is stable, but its native REST APIs
(`/api/v0`, `/api/v1`) still change between releases — check your own
`lms --version` and the LM Studio release notes before assuming an endpoint
behaves as documented here.

Start the LM Studio server (`lms server start`), then:

```sh
bundle exec rake models   # refresh models.json from your local server
bundle exec rake          # rubocop, flay, archspec, specs
```

`rake models` calls the local server's model-listing endpoints and rewrites
the sample `models.json` at the gem root — it is a maintainer task for
refreshing the shipped sample, not something gem users run.

The suite always runs the provider integration specs. The first local run
calls the API and records VCR cassettes; CI only replays committed cassettes.
A failing example deletes its cassette so the next local run tests the live
API again.

After refreshing the catalog, put real model IDs from your machine into
`spec/support/models.rb`. Keep only the operation matrices LM Studio supports
(chat, tools, structured output, embeddings, native chat — where the reasoning
matrix needs a model that emits reasoning items, such as gpt-oss). The
portable contract specs are adapted from
[RubyLLM's live specs](https://github.com/crmne/ruby_llm/tree/main/spec/ruby_llm).
