# ruby_llm-providers-lms

[RubyLLM](https://rubyllm.com) provider gem for [LM Studio](https://lmstudio.ai) — run
local models through LM Studio's OpenAI-compatible server (`lms server start`,
`http://localhost:1234/v1` by default).

The provider works out of the box: no API key, no configuration. It speaks the
Chat Completions dialect by default and also registers the Responses protocol
(LM Studio serves `/v1/responses` too). Model listings are enriched with details
from LM Studio's native REST API (`/api/v0/models`): architecture, quantization,
load state, context length, and tool/vision capabilities.

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'ruby_llm-providers-lms', require: 'ruby_llm/providers/lms'
```

Configuration is optional. Override the defaults only when your server is not
on `http://localhost:1234/v1` or sits behind an auth proxy:

```ruby
require 'ruby_llm/providers/lms'

RubyLLM.configure do |config|
  config.lms_api_base = ENV.fetch('LMS_API_BASE', 'http://localhost:1234/v1')
  config.lms_api_key = ENV['LMS_API_KEY'] # only if your server requires auth
end
```

## Usage

Use the model identifier shown in LM Studio (not an OpenAI model name):

```ruby
chat = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms)
response = chat.ask('Hello')
puts response.content
```

If the server isn't running, requests raise a `RubyLLM::Error` telling you to
start it (`lms server start`) instead of a raw connection failure.

Because LM Studio is a local provider, RubyLLM assumes any model id you pass
exists — LM Studio will just-in-time load the model if it isn't loaded yet.
To browse what the server offers right now, ask the provider directly:

```ruby
provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)
provider.list_models.each { |model| puts model.id }
```

## The model catalog (models.json)

The gem ships a `models.json` at its root. **This file is only a sample**,
recorded from the author's machine: LM Studio serves whatever models *you*
have downloaded, so your catalog will be different. RubyLLM loads the shipped
file as the provider's model registry so `RubyLLM.models` has something to
show.

Note that `RubyLLM.models.refresh` does **not** query your LM Studio server:
provider gems that ship a registry file are excluded from the live fetch, and
refresh just re-reads the registered `models.json`. Your live server is still
the source of truth, reached differently depending on what you need:

- **Chatting** needs no catalog at all — any model id LM Studio knows will
  work (see above).
- **Browsing what your server offers** is `provider.list_models` (see the
  snippet above), which hits the live endpoints every time.
- **Making `RubyLLM.models` reflect your machine** means registering your own
  catalog file in place of the shipped sample:

  ```ruby
  require 'ruby_llm/providers/lms'

  provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)
  RubyLLM::Models.new(provider.list_models).save_to_json('my_models.json')
  RubyLLM::Provider.register :lms, RubyLLM::Providers::LMS, models: 'my_models.json'
  RubyLLM.models.refresh
  ```

Don't edit the `models.json` inside the installed gem — it is overwritten on
every gem update; re-register with your own file instead.

Embeddings work the same way:

```ruby
RubyLLM.embed('Hello world', model: 'text-embedding-nomic-embed-text-v1.5', provider: :lms)
```

To use the Responses dialect instead of Chat Completions:

```ruby
RubyLLM.configure { |config| config.lms_protocol = :responses }
```

## Development

Start the LM Studio server (`lms server start`), then:

```sh
bundle exec rake models   # refresh models.json from your local server
bundle exec rake          # rubocop, flay, archspec, specs
```

`rake models` calls the local server's model-listing endpoints and rewrites
the sample `models.json` at the gem root (see "The model catalog" above) —
it is a maintainer task for refreshing the shipped sample, not something gem
users run.

The suite always runs the provider integration specs. The first local run
calls the API and records VCR cassettes; CI only replays committed cassettes.
A failing example deletes its cassette so the next local run tests the live
API again.

After refreshing the catalog, put real model IDs from your machine into
`spec/support/models.rb`. Keep only the operation matrices LM Studio supports
(chat, tools, structured output, embeddings). The portable contract specs are
adapted from [RubyLLM's live specs](https://github.com/crmne/ruby_llm/tree/main/spec/ruby_llm).
