# Development

```sh
bundle install
bundle exec rake              # rubocop, flay, archspec, specs
bundle exec rspec spec/ruby_llm/chat_spec.rb   # one file
bin/console                   # IRB with the gem loaded
```

Overcommit runs RuboCop, flay, archspec, RSpec and gitleaks as pre-commit
hooks, so the full suite must pass before a commit lands.

## Tested against

| Component | Version |
| --- | --- |
| LM Studio (macOS) | 0.4.24+1 for the chat, embedding and model specs; 0.4.26 for judgments |
| RubyLLM | 2.1.1 (chat cassettes recorded on 2.0.0) |
| Decision models | `kev-0.8b`, `d1-omni-600m`, `clef-flash` (GGUF) |

LM Studio's OpenAI-compatible surface is stable, but its native REST APIs
(`/api/v0`, `/api/v1`) and the decision endpoints still change between
releases. Check your own `lms --version` and the LM Studio release notes before
assuming an endpoint behaves exactly as documented here.

## Specs

Two kinds:

- `spec/ruby_llm/providers/lms_spec.rb` and most of
  `spec/ruby_llm/providers/lms/` — unit specs for the provider: registration,
  protocols, configuration, listing, routing, judgment rendering and parsing.
  The two `*_live_spec.rb` files there are `:live` and record cassettes like
  the contract specs.
- `spec/ruby_llm/*_spec.rb` — contract specs adapted from
  [RubyLLM's live specs](https://github.com/crmne/ruby_llm/tree/main/spec/ruby_llm),
  tagged `:live` and driven by the model matrices in `spec/support/models.rb`.

### VCR cassettes

The first local run of a `:live` example calls the real LM Studio server and
records a cassette in `spec/fixtures/vcr_cassettes/`; later runs replay it. CI
(`CI=1`) only replays committed cassettes, so commit them.

A failing example keeps its cassette, so a red suite stays red. To re-record
deliberately — after a behavior change or an LM Studio upgrade — run with
`RERECORD=1`, which deletes the cassette of any example that fails so the next
run records it fresh:

```sh
RERECORD=1 bundle exec rspec spec/ruby_llm/judgment_spec.rb
```

Cassette URIs are normalized to `http://localhost:1234/v1`, and VCR filters
`LMS_API_BASE` and `LMS_API_KEY` out, so cassettes replay anywhere.

### Model matrices

Model ids are machine-specific. Put ids from `lms ls` into
`spec/support/models.rb` before recording:

| Matrix | Needs |
| --- | --- |
| `CHAT_MODELS`, `TOOL_MODELS` | anything LM Studio serves |
| `TOOL_CHOICE_MODELS` | a model that obeys `tool_choice: "required"` (gpt-oss does not) |
| `STRUCTURED_OUTPUT_MODELS` | a model that does not mangle `json_schema` values (gpt-oss does) |
| `REASONING_MODELS` | a model whose listing reports reasoning options |
| `REASONING_OFF_MODELS` | one of those that also reports LM Studio's `off` |
| `VISION_MODELS` | a model flagged `vision: true` |
| `EMBEDDING_MODELS` | an embedding model |
| `NATIVE_CHAT_MODELS`, `MANAGEMENT_MODEL` | small models, so load/unload cycles stay fast |
| `NATIVE_REASONING_MODELS` | a model that emits reasoning items on the native endpoint (gpt-oss does; most instruct fine-tunes do not) |
| `JUDGMENT_MODELS` | decision models LM Studio tags `type: "decision"`; add `vision: true` for ones with a vision adapter |

Matrices for operations LM Studio doesn't support (image generation, speech,
video, moderation, rerank) are empty, which skips those files.

## The packaged catalog

`bundle exec rake models` rewrites the sample `models.json` from your running
server. It is a maintainer task for refreshing the shipped sample — see
[The Packaged Catalog](../models/catalog.md).

## Architecture checks

`bundle exec rake archspec` enforces the rules in `Archspec.rb`: everything
under `lib/` stays in the `RubyLLM::Providers::LMS` namespace and never
references RSpec, WebMock or VCR. `bundle exec rake flay` flags duplicated code
above a mass of 70.

## Documentation

This site is built with [MkDocs Material](https://squidfunk.github.io/mkdocs-material/)
from `docs/` and `mkdocs.yml`:

```sh
mkdocs serve           # live preview at http://127.0.0.1:8000
mkdocs build --strict  # what the deploy workflow runs; fails on a broken link
```

Pushes to `main` or `develop` that touch `docs/`, `mkdocs.yml` or the workflow
itself publish the site to GitHub Pages
(`.github/workflows/deploy-github-pages.yml`); it can also be run by hand from
the Actions tab.

## CI

`.github/workflows/ci.yml` runs `bundle exec rake` on Ruby 3.3, 3.4 and 4.0.
The committed `Gemfile.lock` must install on every one of them.
