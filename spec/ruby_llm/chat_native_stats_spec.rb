# frozen_string_literal: true

require 'spec_helper'

# The :native_v0 protocol talks to LM Studio's own /api/v0/chat/completions.
# It answers in the OpenAI shape RubyLLM already understands and adds the
# local-inference telemetry the OpenAI-compatible endpoint never reports.
RSpec.describe 'RubyLLM::Chat native protocol', :live do # rubocop:disable RSpec/DescribeClass
  include_context 'with configured RubyLLM'

  each_model(CHAT_MODELS) do |provider, model|
    it "#{provider}/#{model} answers the same way the default protocol does" do
      response = native_chat(model, provider).ask("What's 2 + 2?")

      expect(response.content).to include('4')
      expect(response.role).to eq(:assistant)
      expect(response.tokens.input.to_i).to be_positive
      expect(response.tokens.output.to_i).to be_positive
    end

    it "#{provider}/#{model} reports inference stats through the raw response" do
      body = native_chat(model, provider).ask('What is the capital of France?').raw.body

      expect(body['stats']['tokens_per_second']).to be_positive
      expect(body['stats']['time_to_first_token']).to be >= 0
      expect(body.dig('model_info', 'arch')).to be_a(String)
      expect(body.dig('runtime', 'name')).to be_a(String)
    end
  end

  # A context keeps the protocol override off the global configuration, so
  # the rest of the suite still exercises the default protocol.
  def native_chat(model, provider)
    RubyLLM.context { |config| config.lms_protocol = :native_v0 }
           .chat(model: model, provider: provider, assume_model_exists: true)
  end
end
