# Installation

## 1. LM Studio and its server

Install [LM Studio](https://lmstudio.ai), then start its local server, either
from the app's Developer tab or with the `lms` CLI:

```sh
lms server start
```

The server listens on `http://localhost:1234` by default. If it isn't
running, every request from this gem raises a `RubyLLM::Error` that tells you
to start it, rather than a raw connection failure.

## 2. A model

The gem talks to whatever models you have downloaded. Get one from the app's
search, or with `lms get`:

```sh
lms get qwen/qwen3-4b                                    # a chat model
lms get https://huggingface.co/LiquidAI/d1-omni-600M-GGUF  # a decision model, for judgments
lms ls                                                   # what you have
```

Use the identifiers `lms ls` shows (`qwen/qwen3-4b`, `d1-omni-600m`) as model
ids in Ruby — not OpenAI model names.

## 3. The gem

Add it to your Gemfile:

```ruby
gem 'ruby_llm-providers-lms', require: 'ruby_llm/providers/lms'
```

and `bundle install`. Requiring `ruby_llm/providers/lms` registers the `:lms`
provider with RubyLLM; there is nothing else to set up.

## Requirements

| Component | Version |
| --- | --- |
| Ruby | 3.3 or newer (CI runs 3.3, 3.4 and 4.0) |
| RubyLLM | 2.1.1 or newer |
| LM Studio | any recent build; 0.4.26 or newer for judgments |

See [Development](../development/index.md#tested-against) for the exact
versions the documentation was checked against.
