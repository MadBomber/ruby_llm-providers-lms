# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

RubyLLM provider gem for LM Studio (`ruby_llm-providers-lms`). It registers a
`:lms` provider that talks to LM Studio's local OpenAI-compatible server
(`lms server start`, default `http://localhost:1234/v1`). No API key or
configuration required. Requires Ruby >= 3.3; depends on `ruby_llm >= 2.0.0.rc1`.

## Commands

```sh
bundle exec rake              # full check: rubocop, flay, archspec, specs
bundle exec rspec spec/ruby_llm/chat_spec.rb          # one spec file
bundle exec rspec spec/ruby_llm/chat_spec.rb:9        # one example
bundle exec rake models       # refresh models.json from a running LM Studio server
bundle exec rake flay         # duplicate-code detection (mass threshold 70)
bundle exec rake archspec     # architecture checks (rules in Archspec.rb)
bin/console                   # IRB with the gem loaded
bundle exec rake build        # build the gem into pkg/
```

Overcommit runs rubocop (auto-correct), flay, archspec, rspec, and gitleaks as
pre-commit hooks, so the full suite must pass before any commit lands.

## Architecture

Three source files under `lib/`:

- `lib/ruby_llm/providers/lms.rb` — `RubyLLM::Providers::LMS < Provider`.
  Declares two protocols: `:chat_completions` (a subclass of
  `Protocols::ChatCompletions` that mixes in the `LMS::Models` module) and
  `:responses` (RubyLLM's stock `Protocols::Responses`, since LM Studio also
  serves `/v1/responses`). Registers itself at file load:
  `RubyLLM::Provider.register :lms, ..., models: <path to models.json>`.
  It is a local provider (`local?` returns `true`, no configuration
  requirements); auth headers are sent only when `lms_api_key` is set.
- `lib/ruby_llm/providers/lms/connection_guard.rb` — a `SimpleDelegator`
  around RubyLLM's `Transport::Connection` (wrapped in the provider's
  `initialize`, so every protocol inherits it) that rescues
  `Faraday::ConnectionFailed` and re-raises `RubyLLM::Error` with a
  "start it with `lms server start`" message. Connection refusals bypass
  RubyLLM's error middleware (which only maps HTTP status codes), so
  without this the app would see a raw Faraday exception.
- `lib/ruby_llm/providers/lms/models.rb` — model listing. Fetches the
  OpenAI-compatible `/v1/models` list and enriches each entry with details from
  LM Studio's native REST API (`../api/v0/models` relative to the API base):
  architecture/family, quantization, load state, context length, and
  tool/vision capabilities. The native endpoint is optional — enrichment
  degrades to `{}` when it's unavailable.

`models.json` at the gem root is a packaged fallback catalog that RubyLLM loads
when the provider is registered. It is machine-specific (LM Studio only lists
downloaded models), so it's just a sample; regenerate it with `rake models`.

Architecture rules (`Archspec.rb`): everything under `lib/` must stay in the
`RubyLLM::Providers::LMS` namespace and must never reference `RSpec`,
`WebMock`, or `VCR`.

## Testing

Two kinds of specs:

- `spec/ruby_llm/providers/lms_spec.rb` — unit specs for the provider itself
  (registration, protocols, config, model-listing parsing).
- `spec/ruby_llm/*_spec.rb` — portable contract specs adapted from RubyLLM's
  live specs (https://github.com/crmne/ruby_llm/tree/main/spec/ruby_llm),
  tagged `:live` and driven by the model matrices in `spec/support/models.rb`
  (`CHAT_MODELS`, `TOOL_MODELS`, `STRUCTURED_OUTPUT_MODELS`,
  `EMBEDDING_MODELS`, ...). Matrices for operations LM Studio doesn't support
  (image, speech, video, moderation, rerank) are empty, which skips those files.

VCR workflow (see `spec/spec_helper.rb` and `spec/support/vcr_configuration.rb`):
the first local run of a `:live` example hits the real LM Studio server and
records a cassette in `spec/fixtures/vcr_cassettes/`; later runs replay it. A
failing example deletes its cassette so the next local run re-tests the live
API. CI (`ENV['CI']`) uses `record: :none` and only replays committed
cassettes — so cassettes must be committed for CI to pass.

Model IDs in `spec/support/models.rb` are machine-specific: after refreshing
the catalog, swap in real IDs from `lms ls` (or `models.json`) before
recording cassettes. Note the existing caveat there: gpt-oss models mangle
`json_schema` on LM Studio, so structured-output specs use a qwen3 model.

Local server settings come from `.env` (`LMS_API_BASE`, `LMS_API_KEY`) via
dotenv; VCR filters both out of cassettes.

## CI

`.github/workflows/ci.yml` runs `bundle exec rake` on Ruby 3.3, 3.4, and 4.0
(non-EOL Rubies; keep the matrix in sync with the gemspec's
`required_ruby_version`). The committed `Gemfile.lock` must be installable on
every matrix Ruby — `bundler-cache: true` installs it frozen, so a lockfile
resolved only on a newer Ruby breaks the older jobs at `bundle install`.

VCR cassettes must stay portable: their URIs are normalized to the default
`http://localhost:1234/v1` (see `spec/support/vcr_configuration.rb`) so CI can
replay them without any `LMS_API_BASE` environment variable.
