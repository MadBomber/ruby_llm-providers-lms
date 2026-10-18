# ruby_llm-providers-lms

**A [RubyLLM](https://rubyllm.com) provider for [LM Studio](https://lmstudio.ai):
run local models through the same Ruby API you use for hosted ones.**

```ruby
gem 'ruby_llm-providers-lms', require: 'ruby_llm/providers/lms'
```

```ruby
chat = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms)
chat.ask('Hello').content
```

No API key and no configuration: start LM Studio's server (`lms server start`)
and the `:lms` provider talks to `http://localhost:1234/v1`.

<p align="center" markdown>
[:material-rocket-launch: Get started](getting-started/index.md){ .md-button .md-button--primary }
[:material-scale-balance: Judgments](judgments/index.md){ .md-button }
[:material-github: GitHub](https://github.com/MadBomber/ruby_llm-providers-lms){ .md-button }
</p>

## What it covers

LM Studio serves four families of API on one port, and this gem speaks all of
them:

| API | What you get | Protocols |
| --- | --- | --- |
| [OpenAI](protocols/openai.md) | Chat, streaming, tools, structured output, vision, reasoning, embeddings | `:chat_completions` (default), `:responses` |
| [Anthropic](protocols/anthropic.md) | Claude-style Messages API against a local model | `:anthropic` |
| [Native REST](protocols/native.md) | Inference stats, server-stored conversations, MCP integrations, model management | `:native_v0`, `:native_chat` |
| [Decisions](judgments/index.md) | Typed judgments from decision models: probabilities, choices and scores in milliseconds | `:decisions` (default), `:system_one` |

![How requests reach LM Studio](assets/images/architecture.svg){ .diagram }

## New in 0.3: judgments with decision models

LM Studio 0.4.26 added endpoints for **decision models**: models that answer
typed questions with probabilities instead of writing text. RubyLLM 2.1 calls
these **judgments**, and this gem points them at LM Studio:

```ruby
class TicketTriage < RubyLLM::Judge
  model 'd1-omni-600m', provider: :lms

  probability :urgent, 'Does this need attention today?'
  choice :team, 'Which team should handle this?' do
    billing   'Charges and refunds'
    technical 'Bugs and outages'
  end
  score :frustration, 'How frustrated is the customer?', %w[Calm Annoyed Angry]
end

judgment = TicketTriage.judge('You charged my card twice. Refund it today.')
judgment.urgent.probability  # => 0.97
judgment.team.choice         # => :billing
```

Open-source decision models such as
[D1 Omni 600M](https://huggingface.co/LiquidAI/d1-omni-600M-GGUF) answer in
tens of milliseconds on a laptop. See [Judgments](judgments/index.md).

## The one thing to know first

!!! warning "What a call does depends on two choices, not one"

    LM Studio runs whatever model you downloaded behind every protocol. **The
    protocol decides what is expressible** — `with_schema` is honored on
    `:chat_completions` and silently ignored on `:responses`. **The model
    decides whether it honors what the protocol accepted** — qwen3 obeys
    `tool_choice: "required"`, gpt-oss ignores it. Test against the models you
    intend to ship on. [Choosing a protocol](protocols/index.md) maps the first
    axis.

## Requirements

- Ruby 3.3 or newer
- RubyLLM 2.1.1 or newer
- LM Studio with its server running (0.4.26 or newer for judgments)
