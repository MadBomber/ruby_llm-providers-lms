# ruby_llm-providers-lms

> [!WARNING]
> **What a call does here depends on two choices, not one.** LM Studio serves
> three different API protocols on a single port — OpenAI, Anthropic, and its
> own native REST API — and runs whatever model you have downloaded behind all
> of them. The protocol and the model each decide part of the outcome, and they
> fail in different ways.
>
> **The protocol decides what is expressible.** `with_schema` is honored on
> `:chat_completions` and `:native_v0` and silently ignored on `:responses` and
> `:anthropic` — same model, same schema, prose where you expected JSON.
> Reasoning is spelled `none`/`low`/`medium`/`high`/`xhigh` on the OpenAI
> endpoints and `off`/`low`/`medium`/`high`/`xhigh`/`on` on the native one.
> That much is consistent for every model, and this gem papers over what it can.
>
> **The model decides whether it honors what the protocol accepted**, and no
> amount of provider code can fix that. LM Studio forwards
> `tool_choice: "required"` for anything — qwen3 obeys it, gpt-oss ignores it.
> It constrains generation with a grammar built from your schema, so every
> model returns *structurally* valid JSON — and gpt-oss returns
> `{"name":"analysis","age":0}`, which parses cleanly and means nothing.
> Reasoning support varies per model: some take graded efforts, some only
> on/off, and some cannot be turned off at all.
>
> This is the price of LM Studio's reach. It is all things to all models and
> master of none, where a frontier lab's hosted model treats consistency as a
> feature — one vendor, one protocol, one set of guarantees, held steady on
> their side. Here the matrix is yours to own. Test against the models you
> actually intend to ship on, rather than assuming a capability carries across
> either axis.
>
> [Which protocol should you use?](#which-protocol-should-you-use) maps the
> protocol axis. The model matrices in `spec/support/models.rb` record which
> models were verified to honor what.

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
| LM Studio request extras | yes | yes | yes | yes | sampling only — see below |
| Server-stored conversations | no | no | no | no | yes |
| Reasoning control | yes | yes | **no** | yes | yes |
| Reasoning text returned | yes | yes | no | yes | yes |

Checked against LM Studio 0.4.24+1 (see [Tested against](#tested-against)).
Where a protocol ignores something silently rather than raising, the section
below says so — those are the cases that cost you an afternoon.

"Reasoning control" means `with_thinking` reaches the server. Whether a
given *model* reasons at all is a separate question — see
[Reasoning](#reasoning).

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

## Reasoning

LM Studio honors OpenAI's `reasoning_effort` on `/v1/chat/completions` and
answers with `reasoning_content` and a `reasoning_tokens` count, which RubyLLM
reads into `Message#thinking` and `response.tokens.thinking`:

```ruby
chat = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms)
response = chat.with_thinking(effort: :low).ask('What is 2 + 2?')

response.content              # => "4"
response.thinking.text        # => "The user is asking a simple arithmetic question..."
response.tokens.thinking      # => 40
```

`chat.with_thinking` with no arguments, and `chat.with_thinking(false)`, both
resolve against the model registry: the provider reads each model's
`capabilities.reasoning` from LM Studio's native listing and records it as
RubyLLM reasoning options, so RubyLLM knows which efforts the model takes and
whether it can be switched off at all.

The two chat surfaces spell the vocabulary differently, and the provider
translates between them so your code does not have to:

| | Accepted values |
| --- | --- |
| `/v1/chat/completions`, `/v1/responses`, `/api/v0/chat/completions` | `none`, `minimal`, `low`, `medium`, `high`, `xhigh` |
| `/api/v1/chat` (`:native_chat`) | `off`, `low`, `medium`, `high`, `xhigh`, `on` |
| RubyLLM's registry (what `Model#reasoning_options` reports) | the first row, plus a `:toggle` option where LM Studio offers `on` |

A model that reports no way to stop reasoning — gpt-oss lists only
`low`/`medium`/`high` — makes `with_thinking(false)` raise, which is the
registry telling you the truth about the model rather than a gap in the
catalog.

Reasoning is a per-model trait, and the surfaces differ in how they treat a
model that has none. The OpenAI endpoints accept `reasoning_effort` for any
model and simply ignore it; `POST /api/v1/chat` rejects the request outright:

```
Model 'bible-study-phi3-mini' does not expose reasoning configuration.
```

So on `:native_chat`, only ask for reasoning from a model whose listing
reports it. `with_thinking` and `with_thinking(false)` already refuse
client-side for a model in the registry that reports none; an explicit
`with_thinking(effort:)`, or a model id not in your catalog, reaches the
server and gets the error above.

Which efforts you can ask for depends on what you have downloaded:

```ruby
model = RubyLLM.models.find('qwen/qwen3-4b')
model.supports?(:reasoning)                  # => true
model.reasoning_option_values(:effort)       # => ["none", "low", "medium", "xhigh"]
```

That information comes from the native listing, so it is only in
`RubyLLM.models` for models present in the catalog you registered — see
[The packaged catalog](#the-packaged-catalog-modelsjson).

## Responses — `:responses`

LM Studio also serves OpenAI's newer Responses API at `POST /v1/responses`,
and RubyLLM's stock Responses protocol drives it:

```ruby
RubyLLM.configure { |config| config.lms_protocol = :responses }
```

Streaming, multi-turn conversations and client-side tools all work; the live
specs in `spec/ruby_llm/chat_responses_spec.rb` cover them.

**`with_schema` does not work here** — LM Studio ignores the schema on this
endpoint and nothing raises, so you get unconstrained prose where you expected
JSON. Use `:chat_completions` for structured output.

`with_thinking` works here, reasoning text included. It needs this gem's own
Responses subclass to do so: OpenAI never returns raw reasoning, only an
optional summary, so RubyLLM's stock protocol reads a reasoning item's
`summary`. LM Studio runs the model locally and has nothing to hide, so it
returns the reasoning itself in `content` as `reasoning_text` (and streams it
as `response.reasoning_text.delta`). The provider reads both shapes.

## Embeddings

Embeddings go to `POST /v1/embeddings` regardless of which chat protocol is
in effect — the provider routes them to the OpenAI-compatible endpoint itself,
because that is the only place LM Studio serves them:

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
  `response.raw.body['response_id']`, and also on `response.raw_content`,
  which RubyLLM persists — so a chat reloaded from the database (Rails
  `acts_as_chat`) continues where it left off rather than refusing to replay.
- **Performance stats** — `response.raw.body['stats']` carries tokens per
  second, time to first token, and token counts; `response.tokens` (input,
  output, thinking) is filled from it.
- **Reasoning control** — `chat.with_thinking` maps onto the native
  `reasoning` setting (`off` / `low` / `medium` / `high` / `xhigh` / `on`;
  models accept a subset — gpt-oss takes efforts, most others just on/off).
  RubyLLM's `:none` effort is translated to LM Studio's `off` on the way out.
  Reasoning output comes back separated as `response.thinking.text`, streamed
  as thinking chunks. See [Reasoning](#reasoning).
- **Server-side MCP tools** — pass `with_provider_options(integrations: [...])`
  to have the server itself run MCP plugins from `mcp.json`
  (`{ id: 'mcp/playwright' }`) or ephemeral MCP servers declared in the
  request (`server_label` / `server_url`), with optional `allowed_tools`
  filtering. Executed tool calls appear in `response.raw.body['output']`.
- **Per-request context length** — `with_provider_options(context_length: 8192)`.
- **Opting out of storage** — `with_provider_options(store: false)` keeps the
  conversation off the server, at the cost of multi-turn continuity.

- **Sampling settings** — `top_p`, `top_k`, `min_p` and `repeat_penalty` are
  part of the native request schema, so `with_provider_options(top_k: 40)` and
  friends work here too.

Limitations: no client-side tools (`with_tools` raises — use
`:chat_completions`, or MCP integrations), no structured output
(`with_schema` raises), and image input only as `data_url` parts. Unknown
request keys are rejected, so the request extras that are *not* in the native
schema (`ttl`, `draft_model`) raise a `BadRequestError` here — unlike the
sampling settings above, which the schema does accept.

The endpoint reports no stop reason of its own. When a generation runs into
the `max_output_tokens` the request asked for, the provider reports
`finish_reason: :length` from the token counts rather than claiming the model
stopped on its own.

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
to the id you were given. For the same reason these calls are sent
non-idempotent: RubyLLM retries a POST that times out, and a retried load of a
large model would hold the weights in memory twice. Note that `ttl` is not a load option on the native
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
| `display_name`, `description` | v1 | `"Qwen3 27B"` |
| `params_string`, `size_bytes`, `bits_per_weight` | v1 | `"27B"`, `17742039110`, `4` |
| `variants`, `selected_variant` | v1 | the downloaded quantizations, and which one is selected |
| `reasoning_options` | v1 | `[{type: "effort", values: ["none", "low", "medium", "xhigh"], default: "xhigh"}, {type: "toggle"}]` |
| `loaded_context_length` | v1 | `8192` (the loaded instance's window, which can be smaller than `context_window`) |
| `remaining_ttl_seconds` | v1 | `1050` — how long before an idle JIT-loaded instance evicts |

`Model#capabilities` picks up `function_calling` and `tool_choice` from the
model's tool-use training, `vision` from its vision flag, and `reasoning` from
its reasoning options. `streaming` and `structured_output` hold for every chat
model LM Studio serves: the server constrains generation with a grammar built
from your schema, so structured output works even on weights with no tool
training (whether the *values* are any good is a separate question — see the
gpt-oss caveat in `spec/support/models.rb`).

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

A failing example keeps its cassette, so a red suite stays red. To re-record
against the live server — after a deliberate behavior change, or an LM Studio
upgrade — run with `RERECORD=1`, which deletes the cassette of any example
that fails so the next run records it fresh:

```sh
RERECORD=1 bundle exec rspec spec/ruby_llm/chat_spec.rb
```

After refreshing the catalog, put real model IDs from your machine into
`spec/support/models.rb`. Keep only the operation matrices LM Studio supports;
the ones that need a particular kind of model are commented there:

| Matrix | Needs |
| --- | --- |
| `CHAT_MODELS`, `TOOL_MODELS` | anything LM Studio serves |
| `TOOL_CHOICE_MODELS` | a model that obeys `tool_choice: "required"` (gpt-oss does not) |
| `STRUCTURED_OUTPUT_MODELS` | a model that does not mangle `json_schema` values (gpt-oss does) |
| `REASONING_MODELS` | a model whose listing reports reasoning options |
| `REASONING_OFF_MODELS` | one of those that also reports LM Studio's `off` |
| `VISION_MODELS` | a model flagged `vision: true` |
| `EMBEDDING_MODELS` | an embedding model |
| `NATIVE_CHAT_MODELS`, `NATIVE_REASONING_MODELS`, `MANAGEMENT_MODEL` | small models, so load/unload cycles stay fast |

The portable contract specs are adapted from
[RubyLLM's live specs](https://github.com/crmne/ruby_llm/tree/main/spec/ruby_llm).
