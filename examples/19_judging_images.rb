#!/usr/bin/env ruby
# frozen_string_literal: true

# Judging images: decision models with a vision adapter answer questions
# about pictures, passed with `with:` exactly as for a chat.
#
# The demo draws a few solid-color PNGs (stdlib only, no image library) and
# asks each vision decision model about them, over both decision endpoints.
# The gem sends images as inline base64 data URLs: inside the input for
# /v1/decisions, and in the top-level `images` array for /v1/systemone.
#
#   ruby examples/19_judging_images.rb
#
# Needs a decision model whose listing includes image input, such as
# d1-omni-600m or clef-flash.

require_relative 'common'
require 'tmpdir'
require 'zlib'

SWATCHES = {
  red: [220, 30, 30], green: [30, 170, 60], blue: [30, 60, 220],
  black: [10, 10, 10], white: [250, 250, 250]
}.freeze

QUESTIONS = {
  color: { type: :choice, instructions: 'What color is the image?',
           options: SWATCHES.keys.to_h { |name| [name, nil] } },
  dark: { type: :probability, instructions: 'Is the image dark?' },
  brightness: { type: :score, instructions: 'How bright is the image?', levels: %w[Dark Dim Medium Bright] }
}.freeze

# A minimal truecolor PNG: signature, IHDR, one zlib-compressed IDAT, IEND.
def solid_png(rgb, size: 64)
  chunk = ->(type, data) { [data.bytesize].pack('N') + type + data + [Zlib.crc32(type + data)].pack('N') }
  rows = ([0] + (rgb * size)).pack('C*') * size # filter byte 0, then the pixels
  "\x89PNG\r\n\x1A\n".b + chunk.call('IHDR', [size, size, 8, 2, 0, 0, 0].pack('N2C5')) +
    chunk.call('IDAT', Zlib::Deflate.deflate(rows)) + chunk.call('IEND', '')
end

def vision_decision_models
  RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config).list_models.select do |model|
    model.capabilities.include?('judgment') && model.modalities.input.include?('image')
  end
end

ENDPOINTS = %i[decisions system_one].freeze
HEADER = 'IMAGE   ENDPOINT    COLOR    CONF   DARK BRIGHT'
ROW = '%-7s %-11s %-7s %5.2f %6.2f %6.2f'

models = vision_decision_models
abort 'No decision model with image input found (try d1-omni-600m).' if models.empty?

Dir.mktmpdir do |dir|
  images = SWATCHES.to_h do |name, rgb|
    path = File.join(dir, "#{name}.png")
    File.binwrite(path, solid_png(rgb))
    [name, path]
  end

  models.each do |model|
    puts <<~HEADER
      == #{model.name} (#{model.id}) ==

      #{HEADER}
    HEADER

    images.each do |name, path|
      ENDPOINTS.each do |endpoint|
        # No text is needed: the image alone is the input.
        judgment = RubyLLM.judge(questions: QUESTIONS, with: path, model: model.id, provider: :lms,
                                 context: judgment_context(endpoint))
        puts format(ROW, name, endpoint, judgment.color.choice, judgment.color.confidence,
                    judgment.dark.probability, judgment.brightness.score)
      end
    end
    puts
  end
end

puts <<~SUMMARY
  -- reading this --
  COLOR   the chosen option; CONF is how sure the model is of it
  DARK    probability the image is dark
  BRIGHT  0 Dark .. 3 Bright

  The endpoint can matter more for images than for text. On this author's
  machine D1 Omni 600M named every color correctly over system_one but
  called red "blue" and black "white" over decisions, with or without text
  beside the image; Clef Flash got them all on both. Check your model on
  your endpoint before trusting it with pictures.

  Pass text alongside an image to give it context, for example
  RubyLLM.judge('Customer photo of the delivered box', with: 'box.png', ...).
  A model without a vision adapter (kev-0.8b) is rejected by LM Studio, and
  a non-image attachment such as a PDF raises RubyLLM::UnsupportedAttachmentError
  before any request is sent.
SUMMARY
