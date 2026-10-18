# Configuration

Configuration is optional. The provider has four settings, all on RubyLLM's
configuration object:

| Option | Default | Purpose |
| --- | --- | --- |
| `lms_api_base` | `http://localhost:1234/v1` | Where the server is, ending in `/v1` like the default; the native (`/api/...`) and decision paths are worked out relative to it. |
| `lms_api_key` | `nil` | Sent as a bearer token only when set — for a server behind an auth proxy. |
| `lms_protocol` | `:chat_completions` | Which dialect chats use. See [Choosing a Protocol](../protocols/index.md). |
| `lms_judgment_protocol` | `:decisions` | Which endpoint judgments use. See [Choosing the Endpoint](../judgments/endpoints.md). |

```ruby
require 'ruby_llm/providers/lms'

RubyLLM.configure do |config|
  config.lms_api_base = ENV.fetch('LMS_API_BASE', 'http://localhost:1234/v1')
  config.lms_api_key = ENV['LMS_API_KEY'] # only if your server requires auth
end
```

## Scoping a setting

The protocol options can be set process-wide, for one block of work, or for a
single chat:

```ruby
RubyLLM.configure { |config| config.lms_protocol = :anthropic }   # process-wide

RubyLLM.context { |config| config.lms_protocol = :native_v0 }     # one context
       .chat(model: 'qwen/qwen3-4b', provider: :lms)

RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms,              # one chat
             protocol: :native_chat, assume_model_exists: true)
```

Judgments scope the same way through a context:

```ruby
context = RubyLLM.context { |config| config.lms_judgment_protocol = :system_one }
RubyLLM.judge('...', questions: { ... }, model: 'd1-omni-600m', provider: :lms, context:)
```

## The two protocol settings are independent

`lms_protocol` never affects embeddings or judgments:

- **Embeddings** always go to `POST /v1/embeddings`, the only place LM Studio
  serves them — even when `lms_protocol` is `:anthropic`.
- **Judgments** always go to a decision endpoint, chosen by
  `lms_judgment_protocol`. A chat protocol never handles them.

## A default judgment model

RubyLLM's `default_judgment_model` setting applies when a judgment names no
model. Set it to a decision model you have downloaded so `RubyLLM.judge` and
judge classes without a `model` line work:

```ruby
RubyLLM.configure do |config|
  config.default_judgment_model = 'd1-omni-600m'
end
```

Pass `provider: :lms` on the call (or in the judge class's `model` line) so
RubyLLM routes it to this provider.

## Environment variables in the examples

The scripts in `examples/` read `LMS_API_BASE`, `LMS_API_KEY`, `LMS_MODEL`,
`LMS_EMBEDDING_MODEL`, `LMS_REASONING_MODEL` and `LMS_DECISION_MODEL` (a `.env`
file in the repo root is honored). The gem itself reads no environment
variables.
