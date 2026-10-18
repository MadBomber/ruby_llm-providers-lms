# Models

LM Studio serves whatever models you have downloaded — chat models, embedding
models and decision models — so the provider asks the server what it has
rather than relying on a fixed list.

```ruby
provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)
provider.list_models.each { |model| puts "#{model.id}  #{model.capabilities.join(', ')}" }
```

You don't need a catalog to *use* a model: because `:lms` is a local provider,
RubyLLM assumes any id you pass exists and LM Studio loads it on demand.

## What listing enrichment adds

`list_models` starts from the OpenAI-compatible `/v1/models` listing, which
carries little beyond an id, and merges in LM Studio's native listing. It tries
`GET /api/v1/models` first and falls back to `GET /api/v0/models`; when neither
answers — an older build, or the native API turned off — the plain listing is
still returned.

`Model#name` becomes the display name where one is reported (`"Qwen3 27B"`
rather than `"qwen/qwen3.8-27b"`), and `Model#metadata` picks up whatever the
server knows:

| Key | From | Example |
| --- | --- | --- |
| `owned_by` | the OpenAI listing | `"organization_owner"` |
| `publisher`, `arch`, `quantization`, `compatibility_type`, `state` | v0 and v1 | `"qwen"`, `"qwen35"`, `"Q4_K_M"`, `"gguf"`, `"loaded"` |
| `display_name`, `description` | v1 | `"Qwen3 27B"` |
| `params_string`, `size_bytes`, `bits_per_weight` | v1 | `"27B"`, `17742039110`, `4` |
| `variants`, `selected_variant` | v1 | the downloaded quantizations, and which one is selected |
| `reasoning_options` | v1 | `[{type: "effort", values: ["none", "low", "medium", "xhigh"], default: "xhigh"}, {type: "toggle"}]` |
| `loaded_context_length` | v1 | `8192` — the loaded instance's window, which can be smaller than `context_window` |
| `remaining_ttl_seconds` | v1 | `1050` — how long before an idle JIT-loaded instance evicts |
| `decision_type` | v1, decision models only | `"lfm2-d1-omni"`, `"kev"`, `"clef"` |

## Capabilities

| Kind of model | `capabilities` | `modalities` |
| --- | --- | --- |
| Chat | `streaming`, `structured_output`, plus `function_calling` and `tool_choice` (tool-trained), `vision`, `reasoning` as the listing reports | text in (plus image for vision), text out |
| Embedding | none | text in, embeddings out |
| Decision | `judgment` only | text in (plus image with a vision adapter), `judgment` out |

`streaming` and `structured_output` hold for every chat model LM Studio
serves: the server constrains generation with a grammar built from your
schema, so structured output works even on weights with no tool training —
whether the *values* are any good is a separate question.

Decision models don't chat, so they get the `judgment` capability and output
modality and nothing else. See [Decision Models](../judgments/decision-models.md).

## Model lifecycle: JIT loading, TTL, auto-evict

The server manages memory rather than a fleet:

JIT loading
:   With just-in-time loading enabled (the server default), `/v1/models` lists
    every downloaded model and a request for an unloaded model loads it on
    demand. Expect a long time to first token on that first request. With JIT
    off, only loaded models are served.

TTL
:   JIT-loaded models default to a 60-minute idle TTL. Override it per request
    with the `ttl` [request extra](../protocols/openai.md#lm-studio-request-extras),
    or at load time with `lms load <model> --ttl 3600`. Models loaded
    explicitly with `lms load` have no TTL and stay until unloaded.

Auto-evict
:   By default LM Studio keeps at most one JIT-loaded model in memory,
    evicting the previous one before loading the next. Turn auto-evict off in
    the server settings to keep several resident at once.

The `state` metadata (`loaded` / `not-loaded`) shows which models are resident
right now; [Model Management](management.md) lets you change that from Ruby.
