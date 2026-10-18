# The Anthropic API — `:anthropic`

LM Studio serves Anthropic's Messages API at `POST /v1/messages`, so a codebase
written against Claude can point at a local model without changing how it
talks:

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

## What works

- Plain exchanges
- Streaming, with proper `message_start` / `content_block_delta` SSE events
- Tool calls: `tool_use` blocks with `stop_reason: "tool_use"`, executed as
  ordinary `RubyLLM::Tool` objects in your process
- Reasoning: `with_thinking(effort: :low)` puts Anthropic's `thinking` request
  field on the wire, LM Studio honors it, and the reasoning comes back as a
  `thinking` content block in `response.thinking.text`; `with_thinking(false)`
  turns it off. Anthropic's usage block carries no reasoning token count, so
  `response.tokens.thinking` is `nil` here. Verified on LM Studio 0.4.26.

## What doesn't

!!! danger "`with_schema` is ignored, quietly"

    LM Studio ignores the schema and nothing raises. The same model and
    schema, two protocols:

    ```ruby
    # :chat_completions => {"name": "John", "age": 30}
    # :anthropic        => "Understood. John is 30 years old. How can I help..."
    ```

    Use `:chat_completions` for structured output.

Embeddings and judgments are unaffected: they always go to their own
endpoints.

Example `12_anthropic_protocol.rb` shows streaming, tools and the `with_schema`
trap side by side.
