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
      responses: described_class::Responses,
      native_chat: described_class::NativeChat,
      native_v0: described_class::NativeChatCompletions,
      anthropic: described_class::AnthropicMessages
    )
  end

  it 'keeps chat_completions as the default protocol' do
    expect(described_class.default_protocol).to eq(:chat_completions)
  end

  it 'defaults to the OpenAI-compatible chat endpoint' do
    protocol = described_class::ChatCompletions.new(provider)
    expect(protocol.completion_url).to eq('chat/completions')
  end

  it 'points the native_v0 protocol at the endpoint that reports stats' do
    protocol = described_class::NativeChatCompletions.new(provider)
    expect(protocol.completion_url).to eq('../api/v0/chat/completions')
  end

  # Streaming follows automatically: the protocol's stream_url delegates
  # to completion_url. The live streaming cassette records /v1/messages.
  it 'points the anthropic protocol at messages, relative to the /v1 base' do
    protocol = described_class::AnthropicMessages.new(provider)
    expect(protocol.completion_url).to eq('messages')
  end

  # RubyLLM always lists models through the provider's *default* protocol
  # (Provider#listing_protocol reads self.class.default_protocol, never the
  # configured one), so the enrichment only has to live on :chat_completions.
  # Carrying a second copy on the other protocols was dead weight that implied
  # a routing rule that does not exist.
  it 'keeps the model listing on the default protocol alone' do
    expect(described_class::ChatCompletions).to include(described_class::Models)
    expect(described_class::AnthropicMessages).not_to include(described_class::Models)
    expect(described_class::NativeChat).not_to include(described_class::Models)
  end

  it 'lists models over the OpenAI-compatible endpoint whatever protocol is configured' do
    config.lms_protocol = :anthropic
    listing = described_class.new(config).send(:listing_protocol)

    expect(listing).to eq(described_class::ChatCompletions)
    expect(listing.new(provider).models_url).to eq('models')
  end

  # One spelling of each native path, shared by the listing enrichment and
  # the model-management calls, so the two can never drift apart.
  it 'names the native endpoints in one place' do
    expect(described_class::NATIVE_V1_MODELS_URL).to eq('../api/v1/models')
    expect(described_class::NATIVE_V0_MODELS_URL).to eq('../api/v0/models')

    [described_class::Models, described_class::ModelManagement].each do |consumer|
      expect(consumer.const_defined?(:NATIVE_V1_MODELS_URL, false)).to be(false)
      expect(consumer.const_defined?(:NATIVE_V0_MODELS_URL, false)).to be(false)
    end
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
      it 'derives function calling and tool choice from reported tool_use' do
        expect(protocol.build_capabilities(llm_detail))
          .to eq(%w[streaming structured_output function_calling tool_choice])
      end

      it 'withholds tool choice from a model not trained for tool use' do
        expect(protocol.build_capabilities(vlm_detail)).not_to include('tool_choice')
      end

      # LM Studio constrains generation with a grammar built from the schema,
      # so structured output holds for any LLM it serves, tool-trained or not.
      # Verified against bible-study-phi3-mini, which reports tool_use false
      # and still answers a json_schema request with conforming JSON.
      it 'claims structured output for every chat model the server serves' do
        expect(protocol.build_capabilities(vlm_detail)).to include('structured_output')
      end

      it 'declares reasoning when the listing reports reasoning options' do
        detail = protocol.normalize_v1_detail(
          'type' => 'llm',
          'capabilities' => { 'reasoning' => { 'allowed_options' => %w[off on] } }
        )

        expect(protocol.build_capabilities(detail)).to include('reasoning')
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

    describe '#normalize_v1_detail' do
      let(:v1_model) do
        {
          'type' => 'llm',
          'publisher' => 'qwen',
          'key' => 'qwen/qwen3-27b',
          'display_name' => 'Qwen3 27B',
          'architecture' => 'qwen3',
          'quantization' => { 'name' => 'Q4_K_M', 'bits_per_weight' => 4 },
          'size_bytes' => 17_742_039_110,
          'params_string' => '27B',
          'max_context_length' => 262_144,
          'format' => 'gguf',
          'description' => 'A reasoning model.',
          'variants' => ['qwen/qwen3-27b@q4_k_m', 'qwen/qwen3-27b@q8_0'],
          'selected_variant' => 'qwen/qwen3-27b@q4_k_m',
          'loaded_instances' => [{ 'id' => 'instance',
                                   'config' => { 'context_length' => 8192 },
                                   'remaining_ttl_seconds' => 1050 }],
          'capabilities' => {
            'vision' => true,
            'trained_for_tool_use' => true,
            'reasoning' => { 'allowed_options' => %w[off on], 'default' => 'on' }
          }
        }
      end

      it 'rewrites a v1 entry into the v0 vocabulary and keeps the v1 extras' do
        expect(protocol.normalize_v1_detail(v1_model)).to eq(
          'type' => 'vlm',
          'publisher' => 'qwen',
          'arch' => 'qwen3',
          'compatibility_type' => 'gguf',
          'quantization' => 'Q4_K_M',
          'state' => 'loaded',
          'max_context_length' => 262_144,
          'capabilities' => %w[vision tool_use],
          'display_name' => 'Qwen3 27B',
          'params_string' => '27B',
          'size_bytes' => 17_742_039_110,
          'bits_per_weight' => 4,
          'description' => 'A reasoning model.',
          'variants' => ['qwen/qwen3-27b@q4_k_m', 'qwen/qwen3-27b@q8_0'],
          'selected_variant' => 'qwen/qwen3-27b@q4_k_m',
          'reasoning_options' => [{ 'type' => 'effort', 'values' => %w[none] }, { 'type' => 'toggle' }],
          'loaded_context_length' => 8192,
          'remaining_ttl_seconds' => 1050
        )
      end

      it 'carries the v1-only fields through to model metadata' do
        response = instance_double(Faraday::Response, body: { 'data' => [{ 'id' => 'qwen/qwen3-27b' }] })
        details = { 'qwen/qwen3-27b' => protocol.normalize_v1_detail(v1_model) }
        metadata = protocol.parse_list_models_response(response, 'lms', details: details).first.metadata

        expect(metadata).to include(
          description: 'A reasoning model.',
          variants: ['qwen/qwen3-27b@q4_k_m', 'qwen/qwen3-27b@q8_0'],
          selected_variant: 'qwen/qwen3-27b@q4_k_m',
          bits_per_weight: 4,
          remaining_ttl_seconds: 1050
        )
      end

      it 'reports a model with no loaded instance as not-loaded' do
        detail = protocol.normalize_v1_detail(v1_model.merge('loaded_instances' => []))
        expect(detail['state']).to eq('not-loaded')
        expect(detail).not_to have_key('loaded_context_length')
      end

      it 'drops fields the entry does not carry' do
        expect(protocol.normalize_v1_detail({ 'type' => 'llm' }))
          .to eq('type' => 'llm', 'state' => 'not-loaded', 'capabilities' => [])
      end
    end

    describe '#normalize_v1_type' do
      it 'spells the v1 embedding type the way v0 does' do
        expect(protocol.normalize_v1_type({ 'type' => 'embedding' }, {})).to eq('embeddings')
      end

      it 'turns the v1 vision capability into the v0 model type' do
        expect(protocol.normalize_v1_type({ 'type' => 'llm' }, { 'vision' => true })).to eq('vlm')
      end

      it 'leaves a plain chat model alone' do
        expect(protocol.normalize_v1_type({ 'type' => 'llm' }, {})).to eq('llm')
      end
    end

    describe '#normalize_v1_capabilities' do
      it 'turns the v1 capability flags into v0 capability names' do
        expect(protocol.normalize_v1_capabilities('vision' => true, 'trained_for_tool_use' => true))
          .to eq(%w[vision tool_use])
      end

      it 'omits flags that are false or absent' do
        expect(protocol.normalize_v1_capabilities('vision' => false)).to eq([])
        expect(protocol.normalize_v1_capabilities({})).to eq([])
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

      it 'carries the v1-only details through when the server reports them' do
        metadata = protocol.build_metadata({}, 'display_name' => 'Qwen3 27B', 'params_string' => '27B',
                                               'size_bytes' => 17_742_039_110,
                                               'reasoning_options' => %w[off on],
                                               'loaded_context_length' => 8192)
        expect(metadata).to eq(
          display_name: 'Qwen3 27B',
          params_string: '27B',
          size_bytes: 17_742_039_110,
          reasoning_options: %w[off on],
          loaded_context_length: 8192
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

      it 'names a model by its display name when the native listing reports one' do
        response = instance_double(Faraday::Response, body: { 'data' => [{ 'id' => 'qwen/qwen3-27b' }] })
        models = protocol.parse_list_models_response(
          response, 'lms', details: { 'qwen/qwen3-27b' => { 'display_name' => 'Qwen3 27B' } }
        )
        expect(models.first.name).to eq('Qwen3 27B')
      end

      it 'falls back to the model id when there is no display name' do
        response = instance_double(Faraday::Response, body: { 'data' => [{ 'id' => 'qwen/qwen3-27b' }] })
        expect(protocol.parse_list_models_response(response, 'lms').first.name).to eq('qwen/qwen3-27b')
      end
    end

    describe '#list_models native enrichment' do
      def v1_listing
        { 'models' => [{ 'key' => 'qwen/qwen3-27b', 'display_name' => 'Qwen3 27B', 'architecture' => 'qwen3' }] }
      end

      def v0_listing
        { 'data' => [{ 'id' => 'qwen/qwen3-27b', 'arch' => 'qwen3-from-v0' }] }
      end

      def stub_native(path, status:, body: {})
        stub_request(:get, "http://example.test:1234/api/#{path}/models")
          .to_return(status: status, body: body.to_json, headers: { 'Content-Type' => 'application/json' })
      end

      before do
        stub_request(:get, 'http://example.test:1234/v1/models')
          .to_return(status: 200, body: { 'data' => [{ 'id' => 'qwen/qwen3-27b' }] }.to_json,
                     headers: { 'Content-Type' => 'application/json' })
      end

      it 'prefers the richer v1 listing' do
        stub_native('v1', status: 200, body: v1_listing)
        model = protocol.list_models.first
        expect(model.name).to eq('Qwen3 27B')
        expect(model.family).to eq('qwen3')
      end

      it 'falls back to v0 on a server whose native API has no v1' do
        stub_native('v1', status: 404)
        stub_native('v0', status: 200, body: v0_listing)
        expect(protocol.list_models.first.family).to eq('qwen3-from-v0')
      end

      it 'still lists models when neither native listing answers' do
        stub_native('v1', status: 404)
        stub_native('v0', status: 404)
        model = protocol.list_models.first
        expect(model.id).to eq('qwen/qwen3-27b')
        expect(model.family).to eq('lms')
      end
    end
  end
end
