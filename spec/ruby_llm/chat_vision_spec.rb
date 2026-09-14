# frozen_string_literal: true

require 'spec_helper'

# The provider advertises vision — it maps LM Studio's `vision` capability
# onto image input in the catalog, and the native chat protocol has code to
# render attachments as data_url parts — but nothing exercised either against
# a real server.
RSpec.describe 'RubyLLM::Chat vision', :live do # rubocop:disable RSpec/DescribeClass
  include_context 'with configured RubyLLM'

  let(:image) { File.expand_path('../fixtures/red_square.png', __dir__) }

  each_model(VISION_MODELS) do |provider, model|
    it "#{provider}/#{model} reads an image on the OpenAI endpoint" do
      response = RubyLLM.chat(model: model, provider: provider, assume_model_exists: true)
                        .ask('What color fills this image? Answer with one word.', with: image)

      expect(response.content).to match(/red/i)
    end

    it "#{provider}/#{model} reads an image on the native chat endpoint" do
      response = RubyLLM.chat(model: model, provider: provider,
                              protocol: :native_chat, assume_model_exists: true)
                        .with_provider_options(reasoning: 'off')
                        .ask('What color fills this image? Answer with one word.', with: image)

      expect(response.content).to match(/red/i)
    end

    it "#{provider}/#{model} is listed as accepting image input" do
      listed = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config).list_models.find { |m| m.id == model }

      expect(listed.modalities.input).to include('image')
      expect(listed.supports?(:vision)).to be(true)
    end
  end
end
