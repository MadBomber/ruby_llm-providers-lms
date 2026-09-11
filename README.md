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

Because LM Studio is a local provider, RubyLLM assumes any model id you pass
exists — LM Studio will just-in-time load the model if it isn't loaded yet.
To browse what the server offers:

```ruby
RubyLLM.models.refresh!
RubyLLM.models.by_provider(:lms).each { |model| puts model.id }
```

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

`rake models` calls the local server's model-listing endpoints and writes
`models.json` at the gem root. RubyLLM loads that catalog as a fallback when
this provider is registered. Since LM Studio catalogs are machine-specific
(they list whatever you have downloaded), the packaged catalog is only a
sample — live listings via `RubyLLM.models.refresh!` reflect your machine.

The suite always runs the provider integration specs. The first local run
calls the API and records VCR cassettes; CI only replays committed cassettes.
A failing example deletes its cassette so the next local run tests the live
API again.

After refreshing the catalog, put real model IDs from your machine into
`spec/support/models.rb`. Keep only the operation matrices LM Studio supports
(chat, tools, structured output, embeddings). The portable contract specs are
adapted from [RubyLLM's live specs](https://github.com/crmne/ruby_llm/tree/main/spec/ruby_llm).
