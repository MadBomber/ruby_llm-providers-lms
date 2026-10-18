# The Packaged Catalog

The gem ships a `models.json` at its root, which RubyLLM loads as the
provider's model registry so `RubyLLM.models` has something to show.

!!! warning "This file is only a sample"

    It was recorded from the author's machine. LM Studio serves whatever models
    *you* have downloaded, so your catalog will be different.

`RubyLLM.models.refresh` does **not** query your LM Studio server: provider
gems that ship a registry file are excluded from the live fetch. Refresh still
updates the remote providers, but for `:lms` it only re-reads the registered
`models.json`. Your live server is still the
source of truth, reached differently depending on what you need:

Chatting, embedding, judging
:   Needs no catalog at all — any model id LM Studio knows works.

Browsing what your server offers
:   `provider.list_models`, which hits the live endpoints every time.

Making `RubyLLM.models` reflect your machine
:   Register your own catalog file in place of the shipped sample:

    ```ruby
    require 'ruby_llm/providers/lms'

    provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)
    RubyLLM::Models.new(provider.list_models).save_to_json('my_models.json')
    RubyLLM::Provider.register :lms, RubyLLM::Providers::LMS, models: 'my_models.json'
    RubyLLM.models.refresh
    ```

Some features read the registry rather than the server — notably
[reasoning](../protocols/reasoning.md#what-a-model-supports), which uses each
model's reasoning options to decide what `with_thinking` may ask for. Register
your own catalog to get those right for your models.

Don't edit the `models.json` inside the installed gem — it is overwritten on
every gem update.

For maintainers, `bundle exec rake models` regenerates the shipped sample from
a running server; see [Development](../development/index.md).
