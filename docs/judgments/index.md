# Judgments

LM Studio 0.4.26 added two endpoints for **decision models**: models that
answer typed questions with probabilities instead of generating text. RubyLLM
2.1 calls this a **judgment** (`RubyLLM.judge`, `RubyLLM::Judge`), and this gem
points judgments at LM Studio.

A decision model reads the input once and answers every question with numbers.
There is no output to parse and no format to coax, and it writes nothing — so
it answers in milliseconds. On an M2 Max, D1 Omni 600M answers three questions
about a support ticket in about 30 ms.

![How a judgment reaches a decision model](../assets/images/judgment-flow.svg){ .diagram }

## Three kinds of question

| Type | Ask it with | Answer object | What you read |
| --- | --- | --- | --- |
| probability | `probability :name, 'question?'` | `RubyLLM::Probability` | `probability` — the chance the answer is yes, 0 to 1 |
| choice | `choice :name, 'question?' do ... end` | `RubyLLM::Choice` | `choice` (a Symbol), `probabilities` per option, `confidence` |
| score | `score :name, 'question?', levels` | `RubyLLM::Score` | `score` (can fall between levels), `levels`, `probabilities` per level index, `confidence` |

One call can ask any number of questions; they all ride in a single request.

## Ad hoc: `RubyLLM.judge`

```ruby
review = <<~TEXT
  The blender arrived two days late, which was annoying. But it crushes ice in
  seconds, it is quiet, and smoothies come out perfectly smooth. Best kitchen
  purchase this year.
TEXT

judgment = RubyLLM.judge(
  review,
  questions: {
    satisfied: { type: :probability, instructions: 'Is the customer satisfied with the product?' },
    topic: { type: :choice, instructions: 'What is the review mostly about?',
             options: { shipping: 'Delivery speed or damage in transit', quality: 'How well the product works',
                        support: 'Dealing with customer service', price: 'Cost or value for money' } },
    sentiment: { type: :score, instructions: 'Overall, how does the customer feel about the product?',
                 levels: %w[Furious Unhappy Mixed Happy Delighted] }
  },
  model: 'd1-omni-600m', provider: :lms
)

judgment.satisfied.probability    # => 0.997
judgment.topic.choice             # => :quality
judgment.topic.probabilities      # => {shipping: 0.007, quality: 0.891, support: 0.011, price: 0.09}
judgment.sentiment.score          # => 3.95
judgment.sentiment.levels[judgment.sentiment.score.round]  # => "Delighted"
```

!!! note "Numbers are model- and wording-specific"

    Every figure on these pages came from a real run on the author's machine.
    Small decision models are sensitive to phrasing: shorten that review to
    one sentence and D1 Omni 600M's `satisfied` drops from 0.997 to 0.18,
    while Clef Flash barely moves. See [Patterns and Tuning](patterns.md).

Question hashes take `type:`, `instructions:`, and the type's criteria key:
`criteria:` (yes/no descriptions) for a probability, `options:` for a choice,
`levels:` for a score.

## Reusable: a `RubyLLM::Judge` subclass

Declare the questions once and run the judge over every record:

```ruby
class TicketTriage < RubyLLM::Judge
  model 'd1-omni-600m', provider: :lms

  inputs :teams  # supplied per call; read by the lambda below

  probability :urgent, 'Does this need attention today?'
  choice :team, 'Which team should handle this?', -> { teams }
  score :frustration, 'How frustrated is the customer?', %w[Calm Annoyed Frustrated Angry]
end

judgment = TicketTriage.judge('The API has returned 500 errors for an hour!',
                              teams: { billing: 'Charges and refunds', technical: 'Bugs and outages' })
judgment.team.choice  # => :technical
```

RubyLLM's [judgments guide](https://rubyllm.com/judgments/) covers the whole
DSL: structured (Hash) input, blocks, dynamic options and provider options.

## What a judgment carries

| Method | Returns |
| --- | --- |
| `judgment.<name>` / `judgment[:name]` / `judgment.fetch(:name)` | the answer for one question |
| `judgment.each { \|name, answer\| }` | every answer, in question order |
| `judgment.model` | the instance that answered (`d1-omni-600m`, or `clef-flash:2` for a second instance) |
| `judgment.tokens` | input tokens; output is always 0 |
| `judgment.to_h` | model, answers, tokens and cost as plain data |
| `judgment.raw` | the HTTP response from LM Studio |

Judgments are instrumented as `judgment.ruby_llm` events, like chats.

## Before you start

- You need LM Studio **0.4.26 or newer** and a model LM Studio recognizes as a
  decision model. A chat model is refused. See
  [Decision Models](decision-models.md).
- Two endpoints serve judgments; the default is fine to start with. See
  [Choosing the Endpoint](endpoints.md) — the choice matters more for small
  models than you might expect.
- Models with a vision adapter judge images too: [Judging Images](images.md).
- Wording and thresholds are where the work is: [Patterns and Tuning](patterns.md).
