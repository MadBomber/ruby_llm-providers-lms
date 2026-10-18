# Judging Images

A decision model with a vision adapter answers questions about pictures. Pass
them with `with:`, exactly as for a chat — a path, a URL, or several of either:

```ruby
judgment = RubyLLM.judge(
  questions: {
    damaged: { type: :probability, instructions: 'Is the package damaged?' },
    color: { type: :choice, instructions: 'What color is the box?',
             options: { brown: nil, white: nil, other: nil } }
  },
  with: 'delivery_photo.jpg',
  model: 'clef-flash', provider: :lms
)
```

Text is optional when there is an image; pass it as the first argument to give
the model context (`RubyLLM.judge('Customer photo of the delivered box',
with: 'box.png', ...)`). A judge class takes `with:` the same way:
`TicketTriage.judge(ticket_text, with: screenshot)`.

## Which models

Only models LM Studio reports a vision adapter for — `list_models` shows
`image` among their input modalities. Of the [verified models](decision-models.md),
D1 Omni 600M and Clef Flash read images; Kev 0.8B does not, and LM Studio says
so:

```
kev-0.8b: This server does not support image input for decisions. For a model
that supports it, start it with `--mmproj`
```

A non-image attachment such as a PDF raises
`RubyLLM::UnsupportedAttachmentError` before any request is sent.

## How images travel

Both endpoints take images as inline base64 data URLs — the gem reads the file
and encodes it, so LM Studio never has to fetch anything:

| Endpoint | Where the image goes |
| --- | --- |
| `:decisions` | an `input_image` part in the input's content array, beside an `input_text` part when there is text |
| `:system_one` | a top-level `images` array; `state` carries the text, or `""` when there is none (the endpoint requires it) |

!!! info "Why `:system_one` images needed the gem's help"

    LM Studio's docs say System One accepts "inline base64 data URLs" without
    naming the field, and RubyLLM's stock System One protocol refuses images.
    Testing found the top-level `images` array: a red image scores 0.98-0.996
    on "Is the image red?" and a blue one 0.005-0.07. A Responses-style content
    array in `state` is accepted too, but its image is ignored — the answer
    doesn't change with the picture.

## Results on solid colors

From example `19_judging_images.rb` — five solid swatches, "What color is the
image?" with the five colors as options:

| Image | Clef Flash, decisions | Clef Flash, system_one | D1 Omni 600M, decisions | D1 Omni 600M, system_one |
| --- | --- | --- | --- | --- |
| red | red (0.85) | red (0.98) | **blue** (0.61) | red (0.99) |
| green | green (0.94) | green (0.98) | green (0.99) | green (1.00) |
| blue | blue (0.95) | blue (0.98) | blue (0.27) | blue (0.84) |
| black | black (0.95) | black (0.98) | **white** (0.67) | black (1.00) |
| white | white (0.94) | white (0.97) | white (0.87) | white (0.85) |

Clef Flash is right on both endpoints. D1 Omni 600M is right on every image
over `:system_one` but miscalls two of five over `:decisions`, with or without
text beside the image. The request the gem sends is a plain data URL in both
cases; the difference is in how LM Studio presents the image to that model.

**If you judge images with a small model, use `:system_one`**, and check your
own model on your own images before trusting it.
