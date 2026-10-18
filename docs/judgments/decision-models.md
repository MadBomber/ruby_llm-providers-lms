# Decision Models

A judgment needs a **decision model**: a model built to score typed questions
rather than generate text. Open-source ones are published as GGUF files on
Hugging Face, and LM Studio runs the GGUF builds.

## Models known to work

These three were verified end to end with this gem, over both decision
endpoints:

| Model | Hugging Face | Params | Size | Images | `decision_type` | License |
| --- | --- | --- | --- | --- | --- | --- |
| D1 Omni 600M | [LiquidAI/d1-omni-600M-GGUF](https://huggingface.co/LiquidAI/d1-omni-600M-GGUF) | 600M | 0.8 GB | yes | `lfm2-d1-omni` | Liquid AI's own license |
| Kev 0.8B | [ggml-org/Kev-0.8B-GGUF](https://huggingface.co/ggml-org/Kev-0.8B-GGUF) | 753M | 0.8 GB | no | `kev` | Apache-2.0 |
| Clef Flash | [ggml-org/Clef-Flash-GGUF](https://huggingface.co/ggml-org/Clef-Flash-GGUF) | 9.1B | 7.4 GB | yes | `clef` | Apache-2.0 |

Download with `lms get` and the repository URL:

```sh
lms get https://huggingface.co/LiquidAI/d1-omni-600M-GGUF
lms get https://huggingface.co/ggml-org/Kev-0.8B-GGUF
lms get https://huggingface.co/ggml-org/Clef-Flash-GGUF
```

`lms ls` then lists them under their own **DECISION** heading.

Other repositories tagged
[`decision-model`](https://huggingface.co/models?other=decision-model) on
Hugging Face — the rest of the ggml-org Kev, Clef and vllm-d3 families, Laya,
Julia-1, LiquidAI's d1-3B — should work too, as long as LM Studio lists them as
decision models. Check each license: some (OpenJev, Bespoke-Nimble) are
non-commercial.

## Which one to use

Measured on an M2 Max with the questions from example `18_decision_models.rb`
(one ticket, three questions), warm model:

| Model | Time per judgment | Quality, in practice |
| --- | --- | --- |
| D1 Omni 600M | ~30 ms | Strong on clear-cut text and spam; noticeably sensitive to wording; reads images reliably only over `:system_one` |
| Kev 0.8B | ~65 ms | Least sure of itself; picked the wrong team for an obvious billing ticket and could not spot a gift-card scam |
| Clef Flash | ~600 ms | Most accurate and most consistent across wording and endpoints; reads images over both endpoints |

A reasonable default: **start with D1 Omni 600M**, tune your questions on it,
and move to Clef Flash where the small model's answers aren't trustworthy
enough. Examples 16-20 default to D1 Omni 600M (`LMS_DECISION_MODEL` overrides
it).

## It has to be a decision model to LM Studio

LM Studio decides what counts, and it must say so itself. `GET /api/v1/models`
reports a recognized model with `type: "decision"`:

```json
{ "key": "d1-omni-600m", "type": "decision", "decision_type": "lfm2-d1-omni",
  "has_vision_adapter": true, "architecture": "lfm2", "format": "gguf" }
```

A model that merely shares a decision model's name is not enough. An MLX
conversion of Clef Flash (`mlx-community/clef-flash`) loads as an ordinary LLM,
and both decision endpoints reject it. Use the GGUF repositories above.

A chat model is refused with a `RubyLLM::BadRequestError`:

```
Invalid model identifier "qwen/qwen3.8-27b". Please specify a valid downloaded
model (e.g., d1-omni-600m, kev-0.8b, clef-flash).
```

With no decision model downloaded at all, the message is *"There are no
downloaded decision models."*

## How the gem lists them

`provider.list_models` reports decision models as judgment models, so you can
find them programmatically:

```ruby
provider = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config)
deciders = provider.list_models.select { |model| model.capabilities.include?('judgment') }

deciders.each do |model|
  puts [model.id, model.metadata[:decision_type], model.modalities.input.inspect].join('  ')
end
# clef-flash    clef          ["text", "image"]
# d1-omni-600m  lfm2-d1-omni  ["text", "image"]
# kev-0.8b      kev           ["text"]
```

| Field | For a decision model |
| --- | --- |
| `capabilities` | `["judgment"]` and nothing else — they don't chat |
| `modalities.output` | `["judgment"]` |
| `modalities.input` | `["text"]`, plus `"image"` when LM Studio reports a vision adapter |
| `metadata[:decision_type]` | the kind of decision model, as LM Studio reports it |

## Loading and memory

Decision models load on demand like any other model, with the same idle TTL.
One quirk worth knowing: if you load a model yourself (in the app, or with
`lms load`) and a decision request then loads it on demand, LM Studio can start
a **second instance** beside yours. `lms ps` shows both (`clef-flash` and
`clef-flash:2`), each holding its own memory, and `judgment.model` reports the
instance that answered — `clef-flash:2`, not the model id. Unload the copy you
don't need with `lms unload`.
