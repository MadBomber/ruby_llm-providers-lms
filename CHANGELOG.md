# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- `with_thinking` and `with_thinking(false)` raised `ArgumentError` on every LM
  Studio model. The v1 listing reports each model's reasoning vocabulary under
  `capabilities.reasoning`, but it was recorded as a bare Array of LM Studio's
  own option names — a shape RubyLLM's registry discards — and no model was
  ever given the `reasoning` capability, so `Thinking::Controls` found no
  controls to work with. Reasoning options are now translated into RubyLLM's
  vocabulary (LM Studio's `off` becomes the `none` effort, its `on` becomes a
  `:toggle` option) and models that report them declare `reasoning`. The native
  chat protocol translates `none` back to `off` on the way out, since the two
  endpoints do not share a spelling.
- Embeddings under `config.lms_protocol = :anthropic` raised "Anthropic doesn't
  support embeddings". LM Studio serves `POST /v1/embeddings` on the same port
  whatever chat dialect is in use, so the provider now routes every embedding
  to the OpenAI-compatible protocol rather than the configured chat one.
- `load_model`, `unload_model` and `download_model` were sent as retryable
  POSTs. RubyLLM retries a POST that times out or loses its connection, and
  LM Studio answers a second load of a resident model by starting a second
  instance — so a slow load that timed out could end up holding the weights in
  memory twice. All three are now marked non-idempotent.
- `:native_chat` could not continue a conversation reloaded from the database.
  The `response_id` it continues from was only kept on `Message#raw`, a
  Faraday response that does not survive persistence, so every reloaded
  assistant message looked uncontinuable and the next turn raised. It is now
  also kept on `Message#raw_content`, which RubyLLM persists and rebuilds.
- The `:responses` protocol dropped reasoning text. OpenAI never returns raw
  reasoning, only an optional summary, so RubyLLM's stock protocol reads a
  reasoning item's `summary` and the matching
  `response.reasoning_summary_text.delta` event. LM Studio returns the
  reasoning itself in `content` as `reasoning_text`, streamed as
  `response.reasoning_text.delta`, leaving `summary` empty — so the response
  spent reasoning tokens and `message.thinking` came back nil. A
  `LMS::Responses` subclass now reads both shapes, on the sync and streaming
  paths alike.
- `:native_chat` reported `finish_reason: :stop` for a generation truncated at
  `max_output_tokens`. The native endpoint reports no stop reason, so the
  provider now derives `:length` from the token counts.
- The README claimed `POST /api/v1/chat` rejects every LM Studio request extra.
  It accepts the sampling settings in its own schema — `top_p`, `top_k`,
  `min_p` and `repeat_penalty` — and rejects only the ones that are not in it,
  such as `ttl` and `draft_model`.
- The README claimed the OpenAI-compatible endpoint offers no reasoning
  control. It accepts `reasoning_effort` and answers with `reasoning_content`
  and a `reasoning_tokens` count, all of which RubyLLM already reads.

### Added

- `tool_choice` and `reasoning` capabilities on listed models, alongside the
  `function_calling` and `vision` already derived from the native listing.
- Model metadata now keeps the v1 listing's `description`, `variants`,
  `selected_variant`, `bits_per_weight`, and the loaded instance's
  `remaining_ttl_seconds`.
- Live specs for the `:responses` protocol (conversation, streaming,
  multi-turn, client-side tools, reasoning text and streamed thinking
  chunks), image input on both the OpenAI and native chat endpoints,
  reasoning round-trips, and `tool_choice`.
- README notes which behaviors are traits of the *model* rather than the
  endpoint: whether `tool_choice: "required"` is obeyed, whether structured
  output carries sensible values, and that `POST /api/v1/chat` rejects any
  reasoning setting for a model that exposes no reasoning configuration
  (where the OpenAI endpoints ignore it).

### Changed

- The `:responses` protocol is now `RubyLLM::Providers::LMS::Responses` rather
  than RubyLLM's stock `Protocols::Responses`. Behaviour is unchanged apart
  from the reasoning fix above; code that referenced the stock class by name
  should follow.
- The native endpoint paths are named once on the provider
  (`LMS::NATIVE_V1_MODELS_URL`, `LMS::NATIVE_V0_MODELS_URL`) instead of being
  spelled separately in `Models` and `ModelManagement`.
- `LMS::Models` is no longer mixed into the Anthropic and native chat
  protocols. RubyLLM lists models through the provider's default protocol, so
  the extra copies implied a routing rule that does not exist.
- A failing `:live` example no longer deletes its cassette, which let a real
  regression pass on the next run by re-recording. Pass `RERECORD=1` to get
  the old behavior.
- The published gem no longer ships `spec/` and its VCR cassettes.
- `models.json` regenerated, so the packaged sample carries the reasoning
  options and the v1 fields the listing now keeps. It remains a sample
  recorded from one machine — see the README.

## [0.2.0] - 2026-09-14

### Added

- `:native_chat` protocol for LM Studio's native chat API (`POST /api/v1/chat`).
  The endpoint is stateful — LM Studio stores each response and continues from a
  `response_id` — so the protocol sends only the messages newer than the last
  assistant response and points `previous_response_id` at it, which makes ordinary
  multi-turn `RubyLLM::Chat` work on top of it. Streaming included. Native-only
  options reach the request through `with_provider_options`: `integrations:`
  (MCP plugins or ephemeral MCP servers the server runs itself), `context_length:`,
  and `store: false`.
- `:native_v0` protocol — LM Studio's `POST /api/v0/chat/completions`. Same wire
  shape as the OpenAI-compatible endpoint, but the response carries the `stats`
  block that `/v1/chat/completions` leaves empty (tokens per second, time to first
  token, generation time, stop reason) plus `model_info` and `runtime`, reachable
  through `Message#raw`.
- `:anthropic` protocol — LM Studio also serves Anthropic's Messages API, driven
  by RubyLLM's stock Anthropic protocol with only the request path adjusted.
- Model management on the provider, backed by LM Studio's native REST API:
  `native_models`, `loaded_models`, `load_model` (with an optional
  `context_length:` override), `unload_model`, and `download_model`.
- Model listings read LM Studio's native v1 listing (`/api/v1/models`) when the
  server has one and fall back to the v0 listing otherwise, adding display name,
  parameter count, size on disk, reasoning-effort options, and the loaded
  instance's context length to each model's metadata.
- `RubyLLM::Providers::LMS::VERSION` and `RubyLLM::Providers::LMS.version`.
- Examples 11-15: native inference stats, the Anthropic protocol, the native chat
  protocol, model management, and a protocol capability matrix.

### Changed

- Models are named by their LM Studio display name when the server reports one,
  falling back to the model id.
- The gemspec reads the version from `lib/ruby_llm/providers/lms/version.rb`
  instead of carrying its own literal.

## [0.1.1] - 2026-09-11

### Added

- A friendly `RubyLLM::Error` when the LM Studio server is not running.
  Connection refusals bypass RubyLLM's error middleware, which only maps HTTP
  status codes, so the raw `Faraday::ConnectionFailed` used to surface instead.
- Examples 01-10, covering basic usage, streaming, tools, structured output,
  embeddings, the model catalog, the `:responses` protocol, the connection guard,
  provider options, and provider introspection.

### Fixed

- VCR cassettes replay without `LMS_API_BASE` set, so CI can run them.

### Changed

- CI tests only non-EOL Rubies (3.3, 3.4, 4.0).

## [0.1.0] - 2026-09-11

### Added

- Initial release: a `:lms` provider for RubyLLM that talks to LM Studio's local
  OpenAI-compatible server (`lms server start`, default
  `http://localhost:1234/v1`) with no API key or configuration required.
- `:chat_completions` and `:responses` protocols.
- Model listings enriched from LM Studio's native REST API, plus a packaged
  `models.json` fallback catalog.

[Unreleased]: https://github.com/madbomber/ruby_llm-providers-lms/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/madbomber/ruby_llm-providers-lms/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/madbomber/ruby_llm-providers-lms/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/madbomber/ruby_llm-providers-lms/releases/tag/v0.1.0
