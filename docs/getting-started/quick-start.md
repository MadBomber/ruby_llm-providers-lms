# Quick Start

Every snippet below assumes LM Studio's server is running and the model named
is downloaded.

```ruby
require 'ruby_llm/providers/lms'
```

## Chat

```ruby
chat = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms)
response = chat.ask('Hello')
response.content          # => "Hello! How can I help you today?"
chat.ask('What did I just say?')  # multi-turn context, as with any provider
```

Because LM Studio is a local provider, RubyLLM assumes any model id you pass
exists — it needs no entry in the model registry and no
`assume_model_exists:` — and LM Studio
just-in-time loads the model if it isn't loaded yet. Expect the first request
to a cold model to take a while.

## Streaming

```ruby
chat.ask('Write a haiku about Ruby') { |chunk| print chunk.content }
```

## Tools and structured output

Everything RubyLLM can express works on the default protocol:

```ruby
class Weather < RubyLLM::Tool
  description 'Current weather for a city'
  parameter :city, description: 'City name'

  def execute(city:) = { city:, forecast: 'sunny', celsius: 21 }
end

RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms)
       .with_tools(Weather).ask('What is the weather in Paris?')

schema = { type: 'object', properties: { name: { type: 'string' }, age: { type: 'integer' } },
           required: %w[name age] }
response = RubyLLM.chat(model: 'qwen/qwen3-4b', provider: :lms)
                  .with_schema(schema).ask('John is 30 years old.')
response.content  # => "{\"name\": \"John\", \"age\": 30}"
response.parsed   # => {"name" => "John", "age" => 30}
```

## Embeddings

```ruby
RubyLLM.embed('Hello world', model: 'text-embedding-nomic-embed-text-v1.5', provider: :lms)
```

## A judgment

With a [decision model](../judgments/decision-models.md) downloaded, ask typed
questions and get numbers back:

```ruby
judgment = RubyLLM.judge(
  'The blender arrived late, but it works perfectly. Best purchase this year.',
  questions: {
    satisfied: { type: :probability, instructions: 'Is the customer satisfied with the product?' },
    topic: { type: :choice, instructions: 'What is the review mostly about?',
             options: { shipping: 'Delivery', quality: 'How well it works' } }
  },
  model: 'd1-omni-600m', provider: :lms
)

judgment.satisfied.probability  # => 0.964
judgment.topic.choice           # => :quality
```

## What's on the server

```ruby
provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)
provider.list_models.each { |model| puts "#{model.id}  #{model.capabilities.join(', ')}" }
```

## Next

- [Configuration](configuration.md) — pointing at another host, auth, defaults
- [Choosing a Protocol](../protocols/index.md) — when to leave the default
- [Examples](../examples/index.md) — twenty runnable scripts
