# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::LMS do
  subject(:provider) { described_class.new(config) }

  let(:config) do
    RubyLLM::Configuration.new.tap do |provider_config|
      provider_config.lms_api_base = 'http://example.test:1234/v1'
    end
  end

  it 'is registered with RubyLLM' do
    expect(RubyLLM::Provider.resolve(:lms)).to eq(described_class)
  end

  it 'registers its protocols' do
    expect(described_class.protocols).to include(
      chat_completions: described_class::ChatCompletions,
      responses: RubyLLM::Protocols::Responses
    )
  end

  it 'declares provider configuration' do
    expect(described_class.configuration_options).to eq(%i[lms_api_base lms_api_key])
    expect(described_class.configuration_requirements).to eq([])
  end

  it 'is a local provider with a human-readable name' do
    expect(described_class.local?).to be(true)
    expect(described_class.display_name).to eq('LM Studio')
  end

  it 'uses the configured API base' do
    expect(provider.api_base).to eq('http://example.test:1234/v1')
  end

  it 'defaults to the LM Studio server address' do
    provider = described_class.new(RubyLLM::Configuration.new)
    expect(provider.api_base).to eq('http://localhost:1234/v1')
  end

  it 'sends no Authorization header without an API key' do
    expect(provider.headers).to eq({})
  end

  it 'sends a bearer token when an API key is configured' do
    config.lms_api_key = 'test-key'
    expect(provider.headers).to eq('Authorization' => 'Bearer test-key')
  end

  it 'guards its connection against a server that is not running' do
    expect(provider.connection).to be_a(described_class::ConnectionGuard)
  end

  describe 'model listing' do
    subject(:protocol) do
      described_class::ChatCompletions.new(described_class.new(config))
    end

    let(:llm_detail) do
      {
        'type' => 'llm',
        'arch' => 'qwen2',
        'publisher' => 'lmstudio-community',
        'compatibility_type' => 'gguf',
        'quantization' => 'Q4_K_M',
        'state' => 'loaded',
        'max_context_length' => 32_768,
        'capabilities' => ['tool_use']
      }
    end
    let(:vlm_detail) { { 'type' => 'vlm', 'arch' => 'qwen2_vl' } }
    let(:embedding_detail) { { 'type' => 'embeddings', 'arch' => 'nomic-bert' } }

    describe '#build_modalities' do
      it 'maps chat models to text in and out' do
        expect(protocol.build_modalities(llm_detail)).to eq(input: %w[text], output: %w[text])
      end

      it 'adds image input for vision models' do
        expect(protocol.build_modalities(vlm_detail)).to eq(input: %w[text image], output: %w[text])
      end

      it 'maps embedding models to embedding output' do
        expect(protocol.build_modalities(embedding_detail)).to eq(input: %w[text], output: %w[embeddings])
      end
    end

    describe '#build_capabilities' do
      it 'derives function calling from reported tool_use' do
        expect(protocol.build_capabilities(llm_detail))
          .to eq(%w[streaming structured_output function_calling])
      end

      it 'derives vision from the model type' do
        expect(protocol.build_capabilities(vlm_detail)).to include('vision')
      end

      it 'reports no chat capabilities for embedding models' do
        expect(protocol.build_capabilities(embedding_detail)).to eq([])
      end

      it 'falls back to base capabilities without native details' do
        expect(protocol.build_capabilities({})).to eq(%w[streaming structured_output])
      end
    end

    describe '#build_metadata' do
      it 'keeps native details and drops missing fields' do
        metadata = protocol.build_metadata({ 'owned_by' => 'organization_owner' }, llm_detail)
        expect(metadata).to eq(
          owned_by: 'organization_owner',
          publisher: 'lmstudio-community',
          arch: 'qwen2',
          compatibility_type: 'gguf',
          quantization: 'Q4_K_M',
          state: 'loaded'
        )
      end

      it 'compacts unknown details away' do
        expect(protocol.build_metadata({ 'owned_by' => 'organization_owner' }, {}))
          .to eq(owned_by: 'organization_owner')
      end
    end

    describe '#parse_list_models_response' do
      it 'builds enriched models from the listing and native details' do
        response = instance_double(Faraday::Response,
                                   body: { 'data' => [{ 'id' => 'qwen2.5-7b-instruct',
                                                        'owned_by' => 'organization_owner' }] })
        models = protocol.parse_list_models_response(response, 'lms',
                                                     details: { 'qwen2.5-7b-instruct' => llm_detail })
        expect(models.length).to eq(1)
        model = models.first
        expect(model.id).to eq('qwen2.5-7b-instruct')
        expect(model.provider).to eq('lms')
        expect(model.family).to eq('qwen2')
        expect(model.context_window).to eq(32_768)
        expect(model.capabilities).to include('function_calling')
      end

      it 'builds plain models when native details are unavailable' do
        response = instance_double(Faraday::Response, body: { 'data' => [{ 'id' => 'some-model' }] })
        model = protocol.parse_list_models_response(response, 'lms').first
        expect(model.family).to eq('lms')
        expect(model.capabilities).to eq(%w[streaming structured_output])
      end
    end
  end
end
