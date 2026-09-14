# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
