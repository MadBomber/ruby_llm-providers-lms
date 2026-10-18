# Choosing the Endpoint

LM Studio serves decision models through two endpoints, and the gem has a
protocol for each:

| | `:decisions` (default) | `:system_one` |
| --- | --- | --- |
| Endpoint | `POST /v1/decisions` | `POST /v1/systemone` |
| Origin | OpenAI's Decisions API | Jev (TypeSafe) System One API |
| Input field | `input` | `state` (required) |
| Questions | an array: `{type: predicate \| choice \| score, name, instructions, choices \| levels}` | a hash keyed by name: `{type: noul \| choice \| score, instructions, criteria}` |
| Probability criteria | folded into the instruction text as "Yes: … / No: …" lines | sent as structured `criteria` |
| Images | `input_image` data URLs inside a content array | data URLs in a top-level `images` array |
| Answers | an array with a `name` on each | a hash keyed by question name |

Pick one with `lms_judgment_protocol`:

```ruby
RubyLLM.configure { |config| config.lms_judgment_protocol = :system_one }  # process-wide

context = RubyLLM.context { |config| config.lms_judgment_protocol = :system_one }
RubyLLM.judge(text, questions: { ... }, model: 'd1-omni-600m', provider: :lms, context:)
```

Judgments go to a decision endpoint whatever `lms_protocol` says; a chat
protocol never handles them.

## Do the answers differ?

For a large model, barely. For a small one, sometimes a lot. The two endpoints
phrase the same questions to the model differently, and a 600M-parameter model
notices. From example `18_decision_models.rb`, one billing ticket:

| Model | Endpoint | Urgent | Team | Confidence | Mood (0..2) |
| --- | --- | --- | --- | --- | --- |
| Clef Flash | decisions | 0.96 | billing | 0.96 | 1.21 |
| Clef Flash | system_one | 0.95 | billing | 0.97 | 1.15 |
| D1 Omni 600M | decisions | 0.91 | billing | **0.51** | 0.53 |
| D1 Omni 600M | system_one | 0.91 | billing | **0.94** | 1.08 |
| Kev 0.8B | decisions | 0.64 | billing | 0.66 | 1.03 |
| Kev 0.8B | system_one | 0.64 | billing | 0.70 | 1.21 |

The biggest gap is **probability criteria** — the optional yes/no descriptions
on a probability question. Decisions has no field for them, so RubyLLM folds
them into the instruction text; System One sends them as data:

```ruby
recommend: { type: :probability,
             instructions: 'Would this customer recommend the product to a friend?',
             criteria: { yes: 'Ends satisfied with the product itself', no: 'Would steer others away' } }
```

| Model | decisions | system_one |
| --- | --- | --- |
| Clef Flash | 0.758 | 0.910 |
| D1 Omni 600M | **0.012** | **0.803** |
| Kev 0.8B | 0.602 | 0.788 |

Same model, same question, opposite conclusions. [Images](images.md) show the
same pattern for D1 Omni 600M.

## Recommendation

1. **Pick the endpoint first.** `:decisions` is the default and fine for most
   work; with D1 Omni 600M and either probability criteria or images,
   `:system_one` gave clearly better answers on the author's machine.
2. **Tune on that endpoint.** Thresholds and wording tuned on one endpoint
   don't carry over to the other unchanged.
3. **Prefer guidance in the question text** over criteria when you need to
   switch endpoints: the instruction text reaches the model the same way on
   both.

## Gem-specific details

- **Answers are matched by name.** RubyLLM 2.1.1's stock Decisions protocol
  pairs answers with questions by position; LM Studio returns them in question
  order today, but the gem matches on each answer's `name` so a reordering
  can't silently swap answers. A missing answer raises `RubyLLM::Error`.
- **The System One path** is fixed for an `lms_api_base` that already ends in
  `/v1` (the stock protocol would request `/v1/v1/systemone`).
- **System One images** go in the top-level `images` array, where LM Studio
  reads them; the stock protocol refuses images entirely. See
  [Judging Images](images.md).
