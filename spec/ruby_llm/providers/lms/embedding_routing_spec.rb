# frozen_string_literal: true

require 'spec_helper'

# LM Studio serves POST /v1/embeddings on the same port whichever chat dialect
# you talk, so `lms_protocol` should have no say over where an embedding goes.
# RubyLLM disagrees by default: Provider#embed resolves the *configured*
# protocol, so selecting :anthropic sent embeddings to Anthropic's protocol,
# which refuses them outright rather than falling back to the OpenAI endpoint.
RSpec.describe 'RubyLLM::Providers::LMS embedding routing' do # rubocop:disable RSpec/DescribeClass
  let(:config) do
    RubyLLM::Configuration.new.tap { |configuration| configuration.lms_api_base = 'http://example.test:1234/v1' }
  end

  let(:embedding_body) do
    { 'data' => [{ 'embedding' => [0.1, 0.2, 0.3] }], 'usage' => { 'prompt_tokens' => 3 } }
  end

  def provider_with(protocol)
    config.lms_protocol = protocol
    RubyLLM::Providers::LMS.new(config).tap do |provider|
      allow(provider.connection).to receive(:post)
        .and_return(instance_double(Faraday::Response, body: embedding_body))
    end
  end

  RubyLLM::Providers::LMS.protocols.each_key do |protocol|
    it "embeds over /v1/embeddings under lms_protocol = #{protocol}" do
      provider = provider_with(protocol)

      embedding = provider.embed('Ruby', model: 'text-embedding-nomic-embed-text-v1.5', dimensions: nil)

      expect(embedding.vectors).to eq([0.1, 0.2, 0.3])
      expect(provider.connection).to have_received(:post)
        .with('embeddings', hash_including(model: 'text-embedding-nomic-embed-text-v1.5'), any_args)
    end

    it "renders an embedding payload under lms_protocol = #{protocol}" do
      payload = provider_with(protocol).render_embedding('Ruby', model: 'nomic', dimensions: 256)

      expect(payload).to include(model: 'nomic', input: 'Ruby', dimensions: 256)
    end
  end
end
