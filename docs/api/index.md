# API Reference

Most of what you call is RubyLLM's own API — `RubyLLM.chat`, `RubyLLM.embed`,
`RubyLLM.judge`, `RubyLLM::Judge` — with `provider: :lms`. This page lists what
the gem adds on top. RubyLLM's API is documented at
[rubyllm.com](https://rubyllm.com).

## Loading

```ruby
require 'ruby_llm/providers/lms'
```

Registers the provider as `:lms`, with the packaged `models.json` as its model
registry.

## Configuration options

Set on `RubyLLM.configure` or a `RubyLLM.context`. See
[Configuration](../getting-started/configuration.md).

| Option | Type | Default |
| --- | --- | --- |
| `lms_api_base` | String | `"http://localhost:1234/v1"` |
| `lms_api_key` | String or nil | `nil` |
| `lms_protocol` | Symbol | `:chat_completions` |
| `lms_judgment_protocol` | Symbol | `:decisions` |

## Protocols

| Name | Class | Endpoint |
| --- | --- | --- |
| `:chat_completions` | `RubyLLM::Providers::LMS::ChatCompletions` | `POST /v1/chat/completions` |
| `:responses` | `RubyLLM::Providers::LMS::Responses` | `POST /v1/responses` |
| `:anthropic` | `RubyLLM::Providers::LMS::AnthropicMessages` | `POST /v1/messages` |
| `:native_v0` | `RubyLLM::Providers::LMS::NativeChatCompletions` | `POST /api/v0/chat/completions` |
| `:native_chat` | `RubyLLM::Providers::LMS::NativeChat` | `POST /api/v1/chat` |
| `:decisions` | `RubyLLM::Providers::LMS::Decisions` | `POST /v1/decisions` |
| `:system_one` | `RubyLLM::Providers::LMS::SystemOne` | `POST /v1/systemone` |

`RubyLLM::Providers::LMS.protocols` returns the registry as a Hash.

## The provider instance

```ruby
provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)
```

### Class methods

| Method | Returns |
| --- | --- |
| `LMS.display_name` | `"LM Studio"` |
| `LMS.local?` | `true` |
| `LMS.configuration_options` | `[:lms_api_base, :lms_api_key, :lms_judgment_protocol]` (RubyLLM adds `lms_protocol` for every provider) |
| `LMS.configuration_requirements` | `[]` — nothing is required |
| `LMS.version` / `LMS::VERSION` | the gem version |

### Instance methods

| Method | Returns |
| --- | --- |
| `list_models` | Array of `RubyLLM::Model`, live from the server — see [Models](../models/index.md) |
| `native_models` | Array of Hashes from `GET /api/v1/models` |
| `loaded_models` | the `native_models` with a loaded instance |
| `load_model(model, context_length: nil, **options)` | Hash with `instance_id` |
| `unload_model(instance_id)` | Hash |
| `download_model(model, **options)` | Hash |
| `judgment_protocol` | `:decisions` or `:system_one` — what judgments will use |
| `api_base` | the configured base URL |
| `headers` | `{}`, or the bearer header when `lms_api_key` is set |

See [Model Management](../models/management.md) for the load/unload semantics.

## Judgment answer objects

These are RubyLLM's classes, listed here because they are what decision models
return. See [Judgments](../judgments/index.md).

| Class | Readers |
| --- | --- |
| `RubyLLM::Judgment` | `answers`, `model`, `tokens`, `cost`, `raw`, `to_h`, `[]`, `fetch`, `each`, plus a reader per question name |
| `RubyLLM::Probability` | `probability` |
| `RubyLLM::Choice` | `choice`, `probabilities`, `confidence` |
| `RubyLLM::Score` | `score`, `levels`, `probabilities` (keyed by level index), `confidence` |

## Errors

| Situation | Raised |
| --- | --- |
| Server not running | `RubyLLM::Error` — "Cannot connect to the LM Studio server at …. Start it with `lms server start`." |
| Unknown model, or a chat model asked for a judgment | `RubyLLM::BadRequestError` with LM Studio's message |
| A decision response missing an answer | `RubyLLM::Error` — "LM Studio Decisions returned an invalid judgment" |
| A non-image attachment on a judgment | `RubyLLM::UnsupportedAttachmentError` |
| `with_tools` or `with_schema` on `:native_chat` | `RubyLLM::Error` naming `:chat_completions` as the alternative, before any request is sent |
