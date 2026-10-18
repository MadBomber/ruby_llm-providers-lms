# Patterns and Tuning

## Keep the policy in the judge, the decisions in Ruby

A judge class says what to ask. What to *do* with the answers belongs in plain
Ruby, where thresholds are easy to test and change:

```ruby
URGENT = 0.7
ANGRY = 2.0   # Frustrated or worse on a 0..3 scale
UNSURE = 0.5  # below this team confidence, a person should look

def route(judgment)
  return 'escalate to on-call lead' if judgment.urgent.probability >= URGENT && judgment.frustration.score >= ANGRY
  return 'human triage (team unclear)' if judgment.team.confidence < UNSURE
  return "#{judgment.team.choice} queue, priority" if judgment.urgent.probability >= URGENT

  "#{judgment.team.choice} queue"
end
```

Use `confidence` as a "don't know" signal: a choice with low confidence is a
case for a human, not a coin flip. Example `17_judge_class.rb` routes a small
inbox this way.

## Screen with a decision model, write with a chat model

A decision model answers in tens of milliseconds and writes nothing; a chat
model takes seconds to write a reply. Put the first in front of the second so
the expensive model only sees what deserves it:

```ruby
class ContactScreen < RubyLLM::Judge
  model 'd1-omni-600m', provider: :lms

  probability :spam, 'Is this message spam?'
  probability :needs_reply, 'Does this message need a response from our team?'
  choice :kind, 'What kind of message is this?' do
    question  'Asking how something works or whether we offer it'
    complaint 'Reporting a problem or unhappy with something'
    praise    'Saying thanks or something positive'
    other     'Anything else'
  end
end

inbox.each do |message|
  screen = ContactScreen.judge(message)
  next if screen.spam.probability >= 0.5 || screen.needs_reply.probability < 0.6

  RubyLLM.chat(model: 'qwen/qwen3.8-27b', provider: :lms)
         .with_instructions("Reply briefly to this #{screen.kind.choice}.")
         .ask(message)
end
```

In example `20_judge_then_chat.rb`, screening five messages took 160 ms and
drafting the two that needed replies took about 49 s. Without the screen, the
spam would have gone to the chat model too. The judgment's choice also rides
into the prompt, so the chat model knows what it is answering.

## Wording matters more than you'd think

Small decision models are sensitive to phrasing. Measured while building the
examples:

| Question | D1 Omni 600M | Kev 0.8B | Clef Flash |
| --- | --- | --- | --- |
| "Would this customer recommend the product to a friend?" (glowing review with a late delivery) | 0.22 | 0.90 | 0.95 |
| "Is the customer satisfied with the product?" (same review) | 0.98 | 0.89 | 0.97 |
| "Is this message spam?" (gift-card scam) | 0.95 | 0.29 | 0.95 |
| "Is the sender asking a question or waiting for an answer from us?" (broken-item complaint) | 0.26 | — | — |
| "Does this message need a response from our team?" (same complaint) | 0.80 | 0.65 | 0.95 |

What worked:

- **Short, plain, direct questions.** The wordier "Is this an unsolicited
  advertisement or scam rather than a real customer writing to us?" caught
  spam as well as "Is this message spam?", but it also rated a genuine "Do you
  ship to Canada?" as 0.52 spam on D1 Omni 600M, where the short question gave
  0.02.
- **Ask about the thing itself.** "Is the customer satisfied with the
  product?" rather than a hypothetical like "Would they recommend it?".
- **One condition per question.** If "spam" and "unsolicited marketing" need
  different handling, ask them separately rather than in one question.

And always: test on the model **and** the [endpoint](endpoints.md) you will
deploy on. Criteria in particular can flip a small model's answer between
endpoints.

## Batch the questions, not the requests

Every question in a judge rides in the same request. Adding a question costs
input tokens, not another round trip — ask everything you need in one
judgment rather than calling once per question. `judgment.tokens.input` shows
what a set of questions costs.

## A default model

Set RubyLLM's `default_judgment_model` to a decision model and judge classes
can omit the model (still pass `provider: :lms` on the call):

```ruby
RubyLLM.configure { |config| config.default_judgment_model = 'd1-omni-600m' }
RubyLLM.judge(text, questions: { ... }, provider: :lms)
```
