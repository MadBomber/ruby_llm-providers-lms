# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] - 2026-09-14

### Added

- `:native_chat` protocol for LM Studio's native chat API (`POST /api/v1/chat`).
  The endpoint is stateful — LM Studio stores each response and continues from a
  `response_id` — so the protocol sends only the messages newer than the last
  assistant response and points `previous_response_id` at it, which makes ordinary
  multi-turn `RubyLLM::Chat` work on top of it. The id rides on
  `Message#raw_content`, which RubyLLM persists, so a chat reloaded from the
  database continues rather than refusing to replay. Streaming included.
  Native-only options reach the request through `with_provider_options`:
  `integrations:` (MCP plugins or ephemeral MCP servers the server runs itself),
  `context_length:`, `store: false`, and the sampling settings the native schema
  accepts (`top_p`, `top_k`, `min_p`, `repeat_penalty`). The endpoint reports no
  stop reason of its own, so a generation that runs into `max_output_tokens` is
  reported as `finish_reason: :length` from the token counts.
- `:native_v0` protocol — LM Studio's `POST /api/v0/chat/completions`. Same wire
  shape as the OpenAI-compatible endpoint, but the response carries the `stats`
  block that `/v1/chat/completions` leaves empty (tokens per second, time to first
  token, generation time, stop reason) plus `model_info` and `runtime`, reachable
  through `Message#raw`.
- `:anthropic` protocol — LM Studio also serves Anthropic's Messages API, driven
  by RubyLLM's stock Anthropic protocol with only the request path adjusted.
- Model management on the provider, backed by LM Studio's native REST API:
  `native_models`, `loaded_models`, `load_model` (with an optional
  `context_length:` override), `unload_model`, and `download_model`. All three
  writes are sent non-idempotent: RubyLLM retries a POST that times out, and
  LM Studio answers a second load of a resident model by starting a second
  instance, so a replayed load would hold the weights in memory twice.
- Reasoning control across every protocol that supports it. LM Studio reports
  each model's reasoning vocabulary in its own spelling (`off`, `low`, `medium`,
  `high`, `xhigh`, `on`); the provider translates it into the vocabulary
  RubyLLM's registry reads — `off` becomes the `none` effort, `on` becomes a
  `:toggle` option — so `with_thinking`, `with_thinking(false)` and
  `with_thinking(effort:)` all resolve against what the model actually supports.
  The native endpoint takes a different spelling from the OpenAI ones, so
  `:native_chat` translates `none` back to `off` on the way out.
- `reasoning` and `tool_choice` capabilities on listed models, alongside the
  `function_calling` and `vision` already derived from the native listing.
- Model listings read LM Studio's native v1 listing (`/api/v1/models`) when the
  server has one and fall back to the v0 listing otherwise, adding display name,
  description, parameter count, size on disk, quantization bit width, downloaded
  variants and the selected one, reasoning options, and the loaded instance's
  context length and remaining idle TTL to each model's metadata.
- Embeddings always go to `POST /v1/embeddings`, whichever chat dialect
  `lms_protocol` selects — LM Studio serves them nowhere else, and resolving
  them through the configured chat protocol meant `:anthropic` refused them
  outright.
- `RubyLLM::Providers::LMS::VERSION` and `RubyLLM::Providers::LMS.version`.
- Examples 11-15: native inference stats, the Anthropic protocol, the native chat
  protocol, model management, and a protocol capability matrix.

### Fixed

- The `:responses` protocol dropped reasoning text. OpenAI never returns raw
  reasoning, only an optional summary, so RubyLLM's stock protocol reads a
  reasoning item's `summary` and the matching
  `response.reasoning_summary_text.delta` event. LM Studio returns the reasoning
  itself in `content` as `reasoning_text`, streamed as
  `response.reasoning_text.delta`, leaving `summary` empty — so the response
  spent reasoning tokens and `message.thinking` came back nil. A
  `LMS::Responses` subclass now reads both shapes, on the sync and streaming
  paths alike.
- The published gem no longer ships `spec/` and its VCR cassettes, which are
  recorded conversations with the author's own models.

### Changed

- Models are named by their LM Studio display name when the server reports one,
  falling back to the model id.
- The `:responses` protocol is now `RubyLLM::Providers::LMS::Responses` rather
  than RubyLLM's stock `Protocols::Responses`. Behaviour is unchanged apart from
  the reasoning fix above; code that referenced the stock class by name should
  follow.
- The gemspec reads the version from `lib/ruby_llm/providers/lms/version.rb`
  instead of carrying its own literal.
- A failing `:live` spec no longer deletes its cassette, which let a real
  regression pass on the next run by re-recording itself green. Pass
  `RERECORD=1` to re-record deliberately.

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

[0.2.0]: https://github.com/madbomber/ruby_llm-providers-lms/compare/v0.1.1...v0.2.0
[0.1.1]: https://github.com/madbomber/ruby_llm-providers-lms/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/madbomber/ruby_llm-providers-lms/releases/tag/v0.1.0
