# Reasoning

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

Reasoning works on every chat protocol. On `:anthropic` it travels as
Anthropic's `thinking` request field and comes back as a `thinking` content
block; see [The Anthropic API](anthropic.md).

## What a model supports

`chat.with_thinking` with no arguments, and `chat.with_thinking(false)`, both
resolve against the model registry: the provider reads each model's
`capabilities.reasoning` from LM Studio's native listing and records it as
RubyLLM reasoning options, so RubyLLM knows which efforts the model takes and
whether it can be switched off at all.

```ruby
model = RubyLLM.models.find('qwen/qwen3.8-27b', provider: :lms)
model.supports?(:reasoning)                  # => true
model.reasoning_option_values(:effort)       # => ["none", "low", "medium", "xhigh"]
```

Pass `provider: :lms`: without it, `find` searches the whole registry and can
return another provider's entry for the same model name, with different
reasoning options.

That information comes from the native listing, so it is only in
`RubyLLM.models` for models present in the catalog you registered — see
[The Packaged Catalog](../models/catalog.md).

A model that reports no way to stop reasoning — gpt-oss lists only
`low`/`medium`/`high` — makes `with_thinking(false)` raise when the request is
sent, on `ask`. That is the registry telling you the truth about the model,
not a gap in the catalog.

## Two vocabularies, translated for you

| | Accepted values |
| --- | --- |
| `/v1/chat/completions`, `/v1/responses`, `/api/v0/chat/completions` | `none`, `minimal`, `low`, `medium`, `high`, `xhigh` |
| `/api/v1/chat` (`:native_chat`) | `off`, `low`, `medium`, `high`, `xhigh`, `on` |
| RubyLLM's registry (what `Model#reasoning_options` reports) | the first row, plus a `:toggle` option where LM Studio offers `on` |

The provider translates LM Studio's `off` to RubyLLM's `none` when reading the
listing, and back to `off` when `:native_chat` sends a request.

## Models without reasoning

The surfaces differ in how they treat a model that has none. The OpenAI
endpoints accept `reasoning_effort` for any model and silently ignore it;
`POST /api/v1/chat` rejects the request outright:

```
Model 'bible-study-phi3-mini' does not expose reasoning configuration.
```

So on `:native_chat`, only ask for reasoning from a model whose listing
reports it. `with_thinking` and `with_thinking(false)` refuse before any
request is sent (on `ask`) for a model that reports no reasoning options —
one in the registry without them, or one not in your catalog at all. Only an
explicit `with_thinking(effort:)` reaches the server and gets the error above.
