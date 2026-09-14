# frozen_string_literal: true

require 'spec_helper'

# LM Studio's v1 model listing reports each model's reasoning vocabulary in
# LM Studio's own spelling: capabilities.reasoning.allowed_options is some
# subset of ['off', 'low', 'medium', 'high', 'xhigh', 'on']. RubyLLM's
# registry speaks OpenAI's vocabulary instead — efforts are named
# ['none', 'minimal', 'low', 'medium', 'high', 'xhigh'] and an on/off switch
# is a separate :toggle option — and it reads them from Model#reasoning_options
# as an Array of Hashes, not as bare strings.
#
# Unless the provider translates between the two, Thinking::Controls finds no
# controls at all and both with_thinking and with_thinking(false) raise.
RSpec.describe 'RubyLLM::Providers::LMS reasoning options' do # rubocop:disable RSpec/DescribeClass
  subject(:protocol) { RubyLLM::Providers::LMS::ChatCompletions.new(provider) }

  let(:provider) do
    RubyLLM::Providers::LMS.new(
      RubyLLM::Configuration.new.tap { |config| config.lms_api_base = 'http://example.test:1234/v1' }
    )
  end

  # qwen3.8-27b reports the full vocabulary: efforts plus both switches.
  let(:full_model) do
    model_from(v1_entry(reasoning: { 'allowed_options' => %w[off low medium xhigh on], 'default' => 'xhigh' }))
  end

  # qwen3.6-35b-a3b and most instruct fine-tunes report only the switch.
  let(:toggle_model) do
    model_from(v1_entry(reasoning: { 'allowed_options' => %w[off on], 'default' => 'on' }))
  end

  # gpt-oss-20b reports efforts and no way to turn reasoning off at all.
  let(:effort_model) do
    model_from(v1_entry(reasoning: { 'allowed_options' => %w[low medium high], 'default' => 'low' }))
  end

  let(:plain_model) { model_from(v1_entry(reasoning: nil)) }

  # An entry shaped like GET /api/v1/models returns one, with the reasoning
  # block overridable per example.
  def v1_entry(reasoning:, key: 'test-model')
    {
      'type' => 'llm',
      'key' => key,
      'display_name' => 'Test Model',
      'architecture' => 'qwen35',
      'format' => 'gguf',
      'max_context_length' => 262_144,
      'capabilities' => { 'trained_for_tool_use' => true, 'reasoning' => reasoning }.compact
    }
  end

  # Runs an entry through the whole listing path, so the assertions are about
  # the RubyLLM::Model an application actually gets from #list_models.
  def model_from(entry)
    response = instance_double(Faraday::Response, body: { 'data' => [{ 'id' => entry['key'] }] })
    details = { entry['key'] => protocol.normalize_v1_detail(entry) }
    protocol.parse_list_models_response(response, 'lms', details: details).first
  end

  describe 'the capability the listing reports' do
    it 'declares reasoning for a model whose listing carries reasoning options' do
      expect(full_model.supports?(:reasoning)).to be(true)
    end

    it 'leaves reasoning off a model whose listing carries none' do
      expect(plain_model.supports?(:reasoning)).to be(false)
      expect(plain_model.reasoning_options).to be_empty
    end
  end

  describe 'the option shape RubyLLM reads' do
    it "renames LM Studio's 'off' to the effort RubyLLM spells 'none'" do
      expect(full_model.reasoning_option_values(:effort)).to eq(%w[none low medium xhigh])
    end

    it "reports LM Studio's 'on' as a toggle rather than an effort" do
      expect(full_model.reasoning_option(:toggle)).not_to be_nil
      expect(full_model.reasoning_option_values(:effort)).not_to include('on')
    end

    it 'keeps the listing default as the effort default' do
      expect(full_model.reasoning_option(:effort)[:default]).to eq('xhigh')
    end

    it 'gives a switch-only model a toggle and an off effort but no effort default' do
      expect(toggle_model.reasoning_option(:toggle)).not_to be_nil
      expect(toggle_model.reasoning_option_values(:effort)).to eq(%w[none])
      expect(toggle_model.reasoning_option(:effort)).not_to have_key(:default)
    end

    it 'gives an effort-only model no toggle and no off switch' do
      expect(effort_model.reasoning_option(:toggle)).to be_nil
      expect(effort_model.reasoning_option_values(:effort)).to eq(%w[low medium high])
    end
  end

  # The payoff: these are the calls that raised ArgumentError before the
  # translation existed, on every model LM Studio serves.
  describe 'RubyLLM::Chat#with_thinking' do
    def enable(model) = RubyLLM::Thinking::Config.default.resolve(model)
    def disable(model) = RubyLLM::Thinking::Config.disabled.resolve(model)

    it 'enables thinking at the listing default effort' do
      expect(enable(full_model).effort).to eq(:xhigh)
    end

    it 'disables thinking through the off effort' do
      expect(disable(full_model).effort).to eq(:none)
    end

    it 'enables a switch-only model through its toggle' do
      expect(enable(toggle_model).enabled).to be(true)
    end

    it 'disables a switch-only model through its off effort' do
      expect(disable(toggle_model).effort).to eq(:none)
    end

    it 'enables an effort-only model at its default effort' do
      expect(enable(effort_model).effort).to eq(:low)
    end

    # gpt-oss really cannot stop reasoning, so refusing is the right answer —
    # what matters is that the refusal is about the model, not the catalog.
    it 'still refuses to disable a model that reports no off switch' do
      expect { disable(effort_model) }.to raise_error(ArgumentError, /no off control/)
    end
  end

  # The two chat surfaces disagree about spelling. /v1/chat/completions takes
  # OpenAI's vocabulary (none, minimal, low, medium, high, xhigh) and rejects
  # 'off'; /api/v1/chat takes LM Studio's (off, low, medium, high, xhigh, on)
  # and rejects 'none'. The registry holds OpenAI's, so only the native
  # protocol has to translate on the way out.
  describe 'rendering the resolved effort back onto the wire' do
    def openai_payload(thinking)
      target = instance_double(RubyLLM::Model, id: 'test-model')
      RubyLLM::Providers::LMS::ChatCompletions.new(provider, target)
                                              .render([RubyLLM::Message.new(role: :user, content: 'hi')],
                                                      tools: {}, temperature: nil, thinking: thinking)
    end

    def native_reasoning(thinking)
      RubyLLM::Providers::LMS::NativeChat.new(provider).resolve_reasoning(thinking)
    end

    it 'sends an effort to the OpenAI endpoint unchanged' do
      expect(openai_payload(RubyLLM::Thinking::Config.new(effort: :xhigh))[:reasoning_effort]).to eq('xhigh')
    end

    it "sends 'none' to the OpenAI endpoint, which is how it spells off" do
      expect(openai_payload(RubyLLM::Thinking::Config.new(effort: :none))[:reasoning_effort]).to eq('none')
    end

    it "translates 'none' to 'off' for the native endpoint" do
      expect(native_reasoning(RubyLLM::Thinking::Config.new(effort: :none))).to eq('off')
    end

    it 'sends a shared effort to the native endpoint unchanged' do
      expect(native_reasoning(RubyLLM::Thinking::Config.new(effort: :xhigh))).to eq('xhigh')
    end
  end
end
