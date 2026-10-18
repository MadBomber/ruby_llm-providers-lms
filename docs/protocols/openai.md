# The OpenAI API

The surface most code already targets, and the one with the fewest surprises:
everything RubyLLM can express works.

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

!!! note "Structured output is grammar-constrained"

    LM Studio builds a grammar from your schema, so the JSON is always
    structurally valid — even from weights with no tool training. Whether the
    *values* make sense is up to the model: gpt-oss models mangle
    `json_schema` values on LM Studio, so the specs use a qwen3 model for
    structured output.

## Responses — `:responses`

LM Studio also serves OpenAI's newer Responses API at `POST /v1/responses`:

```ruby
RubyLLM.configure { |config| config.lms_protocol = :responses }
```

Streaming, multi-turn conversations and client-side tools all work.

!!! danger "`with_schema` does not work here"

    LM Studio ignores the schema on this endpoint and nothing raises, so you
    get unconstrained prose where you expected JSON. Use `:chat_completions`
    for structured output.

`with_thinking` works, reasoning text included. That takes this gem's own
Responses subclass: OpenAI never returns raw reasoning, only an optional
summary, so RubyLLM's stock protocol reads a reasoning item's `summary`. LM
Studio runs the model locally and has nothing to hide, so it returns the
reasoning itself in `content` as `reasoning_text` (streamed as
`response.reasoning_text.delta`). The provider reads both shapes.

## Embeddings

Embeddings go to `POST /v1/embeddings` regardless of which chat protocol is in
effect — the provider routes them there itself, because that is the only place
LM Studio serves them:

```ruby
RubyLLM.embed('Hello world', model: 'text-embedding-nomic-embed-text-v1.5', provider: :lms)
```

## LM Studio request extras

LM Studio accepts request fields that are not part of OpenAI's vocabulary.
RubyLLM merges `with_provider_options` into the payload as-is, so these work on
every chat protocol except `:native_chat`, whose server rejects unknown keys:

| Option | What it does |
| --- | --- |
| `ttl` | Idle time-to-live in seconds for the model handling this request. A JIT-loaded model unloads itself after sitting idle that long (default 60 minutes; each request resets the timer). |
| `draft_model` | Speculative decoding: a small draft model proposes tokens the main model verifies, often speeding generation up substantially. Both models must share a tokenizer family. |
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
