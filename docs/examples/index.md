# Examples

Twenty runnable scripts live in
[`examples/`](https://github.com/MadBomber/ruby_llm-providers-lms/tree/main/examples).
Start LM Studio's server, then run any of them from the repo root:

```sh
lms server start
ruby examples/01_basic_usage.rb
ruby examples/run_all.rb        # every numbered demo, in order, with a banner each
```

`examples/common.rb` holds the shared setup: it configures RubyLLM from the
environment (a `.env` file is honored) and defines the default models.

| Variable | Default | Used by |
| --- | --- | --- |
| `LMS_API_BASE` | `http://localhost:1234/v1` | all |
| `LMS_API_KEY` | none | all, only for a server behind auth |
| `LMS_MODEL` | `qwen/qwen3.8-27b` | the chat demos, and the replies in `20` |
| `LMS_EMBEDDING_MODEL` | — | `05` |
| `LMS_REASONING_MODEL` | — | `13` |
| `LMS_DECISION_MODEL` | `d1-omni-600m` | `16`-`20` |

Model ids are machine-specific: use ones `lms ls` shows on your machine.

## Chat, protocols and models

| Script | Shows |
| --- | --- |
| `01_basic_usage.rb` | A one-shot question, a multi-turn conversation, and the token counts every response carries |
| `02_streaming.rb` | Chunks arriving as the model generates them |
| `03_tools.rb` | Function calling with a `RubyLLM::Tool` |
| `04_structured_output.rb` | JSON Schema output via `with_schema`; `response.parsed` gives the Hash |
| `05_embeddings.rb` | Local embeddings and cosine similarity |
| `06_model_catalog.rb` | The live listing enriched from LM Studio's native API |
| `07_responses_protocol.rb` | Switching to the `/v1/responses` dialect |
| `08_connection_guard.rb` | The friendly `RubyLLM::Error` when the server is down |
| `09_provider_options.rb` | LM Studio request extras (`ttl`, `top_k`, `min_p`, `repeat_penalty`, `draft_model`) |
| `10_provider_introspection.rb` | `local?`, `display_name`, configuration options, registered protocols, the optional auth header |
| `11_native_stats.rb` | `:native_v0`: tokens per second, time to first token and runtime |
| `12_anthropic_protocol.rb` | `:anthropic`: streaming, tools, and the `with_schema` trap |
| `13_native_chat.rb` | `:native_chat`: server-stored conversations, reasoning control, and what it gives up |
| `14_model_management.rb` | Listing, loading and unloading models |
| `15_protocol_matrix.rb` | One `with_schema` request through all five chat protocols — which honor it, which raise, which ignore it |

## Judgments with decision models

| Script | Shows |
| --- | --- |
| `16_judgments.rb` | `RubyLLM.judge` with all three question types, and everything a judgment returns |
| `17_judge_class.rb` | A reusable `RubyLLM::Judge` subclass with a runtime input, triaging and routing a support inbox |
| `18_decision_models.rb` | Every decision model you have, over both endpoints, with timings; where the endpoints differ; a chat model refused |
| `19_judging_images.rb` | Image judgments on vision decision models, over both endpoints |
| `20_judge_then_chat.rb` | A decision model screening an inbox so the chat model only drafts the replies that matter |

[Judgment Examples](judgments.md) walks through these five with real output.
