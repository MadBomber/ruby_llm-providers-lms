# Judgment Examples

Examples 16-20 use LM Studio's decision API with open-source decision models.
Each needs at least one [decision model](../judgments/decision-models.md);
they default to D1 Omni 600M:

```sh
lms get https://huggingface.co/LiquidAI/d1-omni-600M-GGUF
ruby examples/16_judgments.rb
LMS_DECISION_MODEL=clef-flash ruby examples/17_judge_class.rb   # try another model
```

The output below is from the author's M2 Max. Your numbers will differ with
model, build and machine.

## 16 — the three question types

Asks a product review two probabilities, a choice and a score in one call, then
prints every answer with its distribution.

```text
satisfied  probability 0.997  ##############################
late       probability 0.987  ##############################
topic      choice      quality (confidence 0.86)
               shipping   0.007
               quality    0.891  ###########################
               support    0.011
               price      0.090  ###
sentiment  score       3.95 of 0..4, nearest "Delighted" (confidence 0.96)
               ...
               Delighted  0.954  #############################

-- the judgment itself --
model:         d1-omni-600m
input tokens:  385
output tokens: 0 (a decision model writes nothing)
round trip:    127 ms (the first call includes loading the model)
```

## 17 — a reusable judge

`TicketTriage < RubyLLM::Judge` with the team list passed in at run time
(`inputs :teams`), and the routing rules in plain Ruby:

```text
TICKET                                         URGENT TEAM        CONF FRUSTR  ROUTE
You charged my card twice this month. I wan...   0.92 billing     0.70    1.9  billing queue, priority
The API has returned 500 errors for an hour...   0.98 technical   0.98    1.8  technical queue, priority
How much would it cost to move our team of ...   0.30 sales       0.77    0.4  sales queue
I forgot my password and the reset email ne...   0.87 accounts    0.91    2.4  escalate to on-call lead
Small thing: the export button tooltip has ...   0.03 technical   0.36    0.1  human triage (team unclear)
```

The last row is the confidence check at work: the model guessed `technical`,
but at 0.36 confidence the router sends it to a person.

## 18 — every decision model, both endpoints

Lists the decision models LM Studio recognizes, judges one ticket with each
over both endpoints, compares probability criteria per endpoint, and shows a
chat model being refused.

```text
ID               DECISION TYPE  PARAMS   SIZE     IMAGES  NAME
clef-flash       clef           9.1B     7.4 GB   yes     Clef Flash
d1-omni-600m     lfm2-d1-omni   600M     0.8 GB   yes     D1 Omni 600M
kev-0.8b         kev            753M     0.8 GB   no      Kev 0.8B

MODEL            ENDPOINT    URGENT TEAM        CONF  MOOD    TIME
clef-flash       decisions     0.96 billing     0.96  1.21   626 ms
clef-flash       system_one    0.95 billing     0.97  1.15   581 ms
d1-omni-600m     decisions     0.91 billing     0.51  0.53    33 ms
d1-omni-600m     system_one    0.91 billing     0.94  1.08    28 ms
kev-0.8b         decisions     0.64 billing     0.66  1.03    70 ms
kev-0.8b         system_one    0.64 billing     0.70  1.21    61 ms
```

The criteria section and what it means are on
[Choosing the Endpoint](../judgments/endpoints.md#do-the-answers-differ). It
loads every decision model you have, so the first run takes a while.

## 19 — judging images

Draws solid-color PNGs with the standard library (no image gem) and asks each
vision decision model what color they are, over both endpoints, with no text
at all — the image is the whole input. Results are tabulated on
[Judging Images](../judgments/images.md#results-on-solid-colors): Clef Flash
is right everywhere; D1 Omni 600M is right over `:system_one` only.

## 20 — screen first, then chat

A `ContactScreen` judge classifies each contact-form message; only the ones
that need a reply go to the chat model (`LMS_MODEL`) for a draft:

```text
reply  spam 0.02  reply 0.80  question  Do you ship to Canada, and if so how long does delivery usua
drop   spam 0.95  reply 0.04  praise    CONGRATULATIONS!!! You have been selected for a $500 gift ca
file   spam 0.00  reply 0.05  praise    Just wanted to say the new dashboard is fantastic. Great wor
reply  spam 0.01  reply 0.80  complaint My order #4417 arrived with a broken handle. What should I d
drop   spam 0.84  reply 0.64  praise    We offer premium SEO backlinks at unbeatable prices. Reply f

Screened 5 messages in 160 ms. 2 need a reply.
...
screening 5 messages: 160 ms with the decision model
drafting 2 replies:   48.7 s with the chat model (including any load time)
```

The questions in this demo were tuned for small models — see
[Patterns and Tuning](../judgments/patterns.md#wording-matters-more-than-youd-think)
for what changed and why.
