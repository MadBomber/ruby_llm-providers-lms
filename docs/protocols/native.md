# The Native REST API

LM Studio's own API, in two generations. **v0** mirrors the OpenAI shapes and
adds telemetry; **v1** is a different design, with server-stored conversations
and model management. The gem uses both.

!!! tip "Path gotcha"

    Model management lives under `/api/v1/models/`, not directly under
    `/api/v1/` — it is `POST /api/v1/models/load`, not `POST /api/v1/load`.

## Inference stats — `:native_v0`

`POST /api/v0/chat/completions` is a strict superset of `/v1/chat/completions`:
the same request — streaming, `with_tools`, `with_schema` and the request
extras all included — and the same `choices` and `usage`, but it fills in the
`stats` block that the OpenAI endpoint returns empty, and adds `model_info` and
`runtime`.

```ruby
RubyLLM.configure { |config| config.lms_protocol = :native_v0 }

response = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms).ask('Hello')
response.raw.body['stats']
# => {"tokens_per_second" => 115.19, "time_to_first_token" => 0.0157,
#     "generation_time" => 0.172, "stop_reason" => "eosFound"}
response.raw.body['runtime']['name']  # => "llama.cpp-mac-arm64-apple-metal-advsimd"
```

RubyLLM has no field for any of this, so it arrives through `Message#raw`.
Everything else behaves identically: this is the default protocol pointed at a
different URL. Reach for it when you want telemetry **and** the full Chat
Completions feature set.

`/v1/chat/completions` returns a `stats` key of its own, but it is `{}` on an
ordinary request; it carries draft-token counts only when the model was loaded
with a `draft_model`. The timing figures, `model_info` and `runtime` are
v0-only.

## Stateful chat — `:native_chat`

`POST /api/v1/chat` offers capabilities the OpenAI surface cannot express:

```ruby
chat = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms,
                    protocol: :native_chat, assume_model_exists: true)
response = chat.ask('Hello')
```

Stateful conversations
:   LM Studio stores each response server-side and continues from a
    `response_id` instead of replaying history. Ordinary RubyLLM multi-turn
    chats just work: each request sends only the new messages and points
    `previous_response_id` at the last stored response. The id is on
    `response.raw.body['response_id']` and on `response.raw_content`, which
    RubyLLM persists — so a chat reloaded from the database (Rails
    `acts_as_chat`) continues where it left off.

Performance stats
:   `response.raw.body['stats']` carries tokens per second, time to first
    token and token counts; `response.tokens` (input, output, thinking) is
    filled from it.

Reasoning control
:   `chat.with_thinking` maps onto the native `reasoning` setting. RubyLLM's
    `:none` effort is sent as LM Studio's `off`. Reasoning comes back as
    `response.thinking.text`, streamed as thinking chunks. See
    [Reasoning](reasoning.md).

Server-side MCP tools
:   `with_provider_options(integrations: [...])` has the server itself run MCP
    plugins from `mcp.json` (`{ id: 'mcp/playwright' }`) or ephemeral MCP
    servers declared in the request (`server_label` / `server_url`), with
    optional `allowed_tools` filtering. Executed tool calls appear in
    `response.raw.body['output']`.

Per-request context length
:   `with_provider_options(context_length: 8192)`.

Opting out of storage
:   `with_provider_options(store: false)` keeps the conversation off the
    server. The chat is then single-turn: a second `ask` raises, because the
    endpoint cannot replay history and has nothing stored to continue from.

Sampling settings
:   `top_p`, `top_k`, `min_p` and `repeat_penalty` are part of the native
    schema, so `with_provider_options(top_k: 40)` works here too.

### Limitations

- No client-side tools: `with_tools` raises. Use `:chat_completions`, or MCP
  integrations.
- No structured output: `with_schema` raises.
- Image input only as `data_url` parts.
- Unknown request keys are rejected, so `ttl` and `draft_model` raise a
  `BadRequestError` here.

The endpoint reports no stop reason of its own. When a generation runs into
the `max_output_tokens` the request asked for, the provider reports
`finish_reason: :length` from the token counts. (Note the spelling: RubyLLM's
stock protocols report truncation as `:max_tokens`.)

## Model listing and management

The native listings enrich `provider.list_models`, and the v1 management
endpoints back the provider's `load_model`, `unload_model` and friends. See
[Models](../models/index.md) and [Model Management](../models/management.md).
