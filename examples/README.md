# Examples

Runnable demos for the LMS provider. Start LM Studio's server first
(`lms server start`), then run any script from the repo root:

```sh
ruby examples/01_basic_usage.rb
```

Or run the whole numbered sequence with a banner before each demo:

```sh
ruby examples/run_all.rb
```

`common.rb` holds the shared setup: it configures RubyLLM from the
environment (a `.env` file is honored) and defines the default model.
Override with `LMS_API_BASE`, `LMS_API_KEY`, `LMS_MODEL`, or
`LMS_EMBEDDING_MODEL`.

| Script | Shows |
|---|---|
| `01_basic_usage.rb` | One-shot ask, multi-turn context, token counts |
| `02_streaming.rb` | Chunks arriving as the model generates |
| `03_tools.rb` | Function calling with a `RubyLLM::Tool` |
| `04_structured_output.rb` | JSON Schema output via `with_schema` |
| `05_embeddings.rb` | Local embeddings and cosine similarity |
| `06_model_catalog.rb` | Live listing enriched from LM Studio's native API |
| `07_responses_protocol.rb` | Switching to the `/v1/responses` dialect |
| `08_connection_guard.rb` | Friendly `RubyLLM::Error` when the server is down |
| `09_provider_options.rb` | LM Studio-only request fields (`ttl`, `top_k`, `min_p`, `repeat_penalty`, `draft_model`) via `with_provider_options` |
| `10_provider_introspection.rb` | The provider's own methods: `local?`, `display_name`, config options, optional auth header |
