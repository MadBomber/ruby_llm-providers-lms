# Choosing a Protocol

LM Studio speaks several APIs on one port, and runs whatever model you have
downloaded behind all of them. This gem registers a protocol for each:

| API | Endpoints | Protocols |
| --- | --- | --- |
| [OpenAI](openai.md) | `POST /v1/chat/completions`, `POST /v1/responses`, `GET /v1/models`, `POST /v1/embeddings` | `:chat_completions` (default), `:responses` |
| [Anthropic](anthropic.md) | `POST /v1/messages` | `:anthropic` |
| [Native REST](native.md) | v0: `POST /api/v0/chat/completions`, `GET /api/v0/models` <br> v1: `POST /api/v1/chat`, `GET /api/v1/models`, `POST /api/v1/models/load`, `/unload`, `/download` | `:native_v0`, `:native_chat` |
| [Decisions](../judgments/endpoints.md) | `POST /v1/decisions`, `POST /v1/systemone` | `:decisions` (default for judgments), `:system_one` |

The first three APIs carry the five **chat** protocols, selected with
`lms_protocol`. The
decision protocols serve only judgments and are selected separately with
`lms_judgment_protocol` — see [Configuration](../getting-started/configuration.md).

## Two choices, not one

!!! warning "The protocol and the model each decide part of the outcome"

    **The protocol decides what is expressible.** `with_schema` is honored on
    `:chat_completions` and `:native_v0` and silently ignored on `:responses`
    and `:anthropic` — same model, same schema, prose where you expected JSON.
    Reasoning is spelled `none`/`minimal`/`low`/`medium`/`high`/`xhigh` on the OpenAI
    endpoints and `off`/`low`/`medium`/`high`/`xhigh`/`on` on the native one.
    That much is consistent for every model, and this gem papers over what it
    can.

    **The model decides whether it honors what the protocol accepted**, and no
    provider code can fix that. LM Studio forwards `tool_choice: "required"`
    for anything — qwen3 obeys it, gpt-oss ignores it. It constrains generation
    with a grammar built from your schema, so every model returns
    *structurally* valid JSON — and gpt-oss returns
    `{"name":"analysis","age":0}`, which parses cleanly and means nothing.

    This is the price of LM Studio's reach: it is all things to all models.
    Test against the models you actually intend to ship on, rather than
    assuming a capability carries across either axis.

## The chat protocols compared

Stay on the default unless you need something only another column offers.

| | `:chat_completions` | `:responses` | `:anthropic` | `:native_v0` | `:native_chat` |
| --- | --- | --- | --- | --- | --- |
| Streaming | yes | yes | yes | yes | yes |
| Client-side tools (`with_tools`) | yes | yes | yes | yes | **no** — raises; use MCP integrations |
| Structured output (`with_schema`) | yes | **ignored, silently** | **ignored, silently** | yes | **no** — raises |
| Inference stats | no | no | no | yes, via `raw` | yes, via `tokens` |
| LM Studio request extras | yes | yes | yes | yes | sampling settings only — see [Native REST API](native.md) |
| Server-stored conversations | no | no | no | no | yes |
| Reasoning control | yes | yes | yes | yes | yes |
| Reasoning text returned | yes | yes | yes | yes | yes |

Checked against LM Studio 0.4.24+1; the `:anthropic` reasoning rows and the
decision endpoints against 0.4.26. The cells that say the server *ignores*
something describe observed behavior, not anything the gem enforces.

Where a protocol ignores something silently rather than raising, its page says
so — those are the cases that cost you an afternoon. Example
`15_protocol_matrix.rb` runs the `with_schema` row against your own models.

"Reasoning control" means `with_thinking` reaches the server. Whether a given
*model* reasons at all is a separate question — see [Reasoning](reasoning.md).

## Selecting one

```ruby
RubyLLM.configure { |config| config.lms_protocol = :anthropic }      # process-wide

RubyLLM.context { |config| config.lms_protocol = :native_v0 }        # one context
       .chat(model: 'qwen/qwen3-4b', provider: :lms)

RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms,                 # one chat
             protocol: :native_chat, assume_model_exists: true)
```

Whatever `lms_protocol` says, embeddings go to `/v1/embeddings` and judgments
go to a decision endpoint.
