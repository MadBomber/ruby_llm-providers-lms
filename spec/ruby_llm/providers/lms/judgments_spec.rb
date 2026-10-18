# frozen_string_literal: true

require 'spec_helper'

# LM Studio 0.4.26 serves decision models through two endpoints: OpenAI's
# Decisions API (POST /v1/decisions) and the Jev System One API
# (POST /v1/systemone). RubyLLM.judge reaches either one through LMS#judge.
RSpec.describe 'RubyLLM::Providers::LMS judgments' do # rubocop:disable RSpec/DescribeClass
  let(:config) do
    RubyLLM::Configuration.new.tap { |configuration| configuration.lms_api_base = 'http://example.test:1234/v1' }
  end

  let(:model) { RubyLLM::Model.new(id: 'decision-model', provider: 'lms') }

  let(:questions) do
    {
      urgent: RubyLLM::Judge::Question.new(:urgent, type: :probability,
                                                    instructions: 'Does this need attention today?'),
      department: RubyLLM::Judge::Question.new(:department, type: :choice, instructions: 'Which team?',
                                                            criteria: { billing: 'Payments', other: nil }),
      frustration: RubyLLM::Judge::Question.new(:frustration, type: :score, instructions: 'How frustrated?',
                                                              criteria: %w[Calm Angry])
    }
  end

  # Answers deliberately out of question order: they are matched by name.
  let(:decisions_body) do
    {
      'model' => 'decision-model',
      'answers' => [
        { 'type' => 'score', 'name' => 'frustration', 'score' => 0.8, 'confidence' => 0.7,
          'probabilities' => [{ 'value' => 0, 'label' => '0', 'probability' => 0.2 },
                              { 'value' => 1, 'label' => '1', 'probability' => 0.8 }] },
        { 'type' => 'predicate', 'name' => 'urgent', 'probability' => 0.93 },
        { 'type' => 'choice', 'name' => 'department', 'choice' => 'billing', 'confidence' => 0.9,
          'probabilities' => [{ 'value' => 'billing', 'probability' => 0.95 },
                              { 'value' => 'other', 'probability' => 0.05 }] }
      ],
      'usage' => { 'input_tokens' => 42, 'output_tokens' => 0 }
    }
  end

  let(:system_one_body) do
    {
      'model' => 'decision-model',
      'answers' => {
        'urgent' => { 'noul' => 0.93 },
        'department' => { 'choice' => 'billing', 'confidence' => 0.9,
                          'probabilities' => { 'billing' => 0.95, 'other' => 0.05 } },
        'frustration' => { 'score' => 0.8, 'confidence' => 0.7, 'legend' => { '0' => 'Calm', '1' => 'Angry' },
                           'probabilities' => { '0' => 0.2, '1' => 0.8 } }
      },
      'usage' => { 'input_tokens' => 42, 'output_tokens' => 0 }
    }
  end

  def provider_answering(body, protocol: nil, judgment_protocol: nil)
    config.lms_protocol = protocol
    config.lms_judgment_protocol = judgment_protocol
    RubyLLM::Providers::LMS.new(config).tap do |provider|
      allow(provider.connection).to receive(:post).and_return(instance_double(Faraday::Response, body: body))
    end
  end

  describe 'routing' do
    RubyLLM::Providers::LMS.protocols.each_key do |protocol|
      it "judges over /v1/decisions under lms_protocol = #{protocol}" do
        provider = provider_answering(decisions_body, protocol: protocol)

        provider.judge('I was charged twice.', questions: questions, model: model)

        expect(provider.connection).to have_received(:post)
          .with('decisions', hash_including(model: 'decision-model', input: 'I was charged twice.'), any_args)
      end
    end

    it 'judges over /v1/systemone when lms_judgment_protocol selects it' do
      provider = provider_answering(system_one_body, protocol: :anthropic, judgment_protocol: :system_one)

      provider.judge('I was charged twice.', questions: questions, model: model)

      expect(provider.connection).to have_received(:post)
        .with('systemone', hash_including(model: 'decision-model', state: 'I was charged twice.'), any_args)
    end

    it 'defaults to the Decisions endpoint' do
      expect(RubyLLM::Providers::LMS.new(config).judgment_protocol).to eq(:decisions)
    end
  end

  describe RubyLLM::Providers::LMS::Decisions do
    subject(:protocol) { described_class.new(RubyLLM::Providers::LMS.new(config), model) }

    it 'renders all three question types in the Decisions vocabulary' do
      payload = protocol.render_judgment_payload('I was charged twice.', questions: questions, model: 'decision-model')

      expect(payload[:questions]).to eq(
        [
          { type: 'predicate', name: 'urgent', instructions: 'Does this need attention today?' },
          { type: 'choice', name: 'department', instructions: 'Which team?',
            choices: [{ value: 'billing', description: 'Payments' }, { value: 'other' }] },
          { type: 'score', name: 'frustration', instructions: 'How frustrated?',
            levels: [{ label: '0', description: 'Calm' }, { label: '1', description: 'Angry' }] }
        ]
      )
    end

    it 'sends an image as an inline data URL, as LM Studio requires' do
      image = RubyLLM::Attachment.new(File.expand_path('../../../fixtures/red_square.png', __dir__))

      payload = protocol.render_judgment_payload('Is it red?', questions: questions, model: 'decision-model',
                                                               with: [image])

      content = payload[:input].first[:content]
      expect(content.first).to eq(type: 'input_text', text: 'Is it red?')
      expect(content.last[:image_url]).to start_with('data:image/png;base64,')
    end

    it 'matches answers to questions by name, whatever order they arrive in' do
      judgment = protocol.parse_judgment_response(instance_double(Faraday::Response, body: decisions_body),
                                                  questions: questions)

      expect(judgment.urgent.probability).to eq(0.93)
      expect(judgment.department.choice).to eq(:billing)
      expect(judgment.department.probabilities).to eq(billing: 0.95, other: 0.05)
      expect(judgment.frustration.score).to eq(0.8)
      expect(judgment.frustration.probabilities).to eq(0 => 0.2, 1 => 0.8)
      expect(judgment.tokens.input).to eq(42)
    end

    it 'falls back to the requested model id when the response names none' do
      body = decisions_body.except('model')

      judgment = protocol.parse_judgment_response(instance_double(Faraday::Response, body: body), questions: questions)

      expect(judgment.model).to eq('decision-model')
    end

    it 'raises a RubyLLM::Error when a question goes unanswered' do
      body = decisions_body.merge('answers' => decisions_body['answers'].take(1))

      expect { protocol.parse_judgment_response(instance_double(Faraday::Response, body: body), questions: questions) }
        .to raise_error(RubyLLM::Error, /LM Studio Decisions returned an invalid judgment/)
    end
  end

  describe RubyLLM::Providers::LMS::SystemOne do
    subject(:protocol) { described_class.new(RubyLLM::Providers::LMS.new(config), model) }

    it 'posts to systemone beside the /v1 api_base' do
      expect(protocol.judgment_url).to eq('systemone')
    end

    it 'sends images in a top-level images array of inline data URLs' do
      image = RubyLLM::Attachment.new(File.expand_path('../../../fixtures/red_square.png', __dir__))

      payload = protocol.render_judgment_payload('Is it red?', questions: questions, model: 'decision-model',
                                                               with: [image])

      expect(payload[:state]).to eq('Is it red?')
      expect(payload[:images]).to contain_exactly(start_with('data:image/png;base64,'))
    end

    it 'sends an empty state with an image judged without text, since state is required' do
      image = RubyLLM::Attachment.new(File.expand_path('../../../fixtures/red_square.png', __dir__))

      payload = protocol.render_judgment_payload(nil, questions: questions, model: 'decision-model', with: [image])

      expect(payload[:state]).to eq('')
    end

    it 'leaves images out when there are none' do
      payload = protocol.render_judgment_payload('Is it red?', questions: questions, model: 'decision-model')

      expect(payload).not_to have_key(:images)
    end

    it 'refuses an attachment that is not an image' do
      document = instance_double(RubyLLM::Attachment, image?: false, mime_type: 'application/pdf')

      expect { protocol.render_images([document]) }.to raise_error(RubyLLM::UnsupportedAttachmentError)
    end

    it 'parses noul, choice, and score answers' do
      judgment = protocol.send(:parse_judgment_response, instance_double(Faraday::Response, body: system_one_body),
                               questions: questions)

      expect(judgment.urgent.probability).to eq(0.93)
      expect(judgment.department.choice).to eq(:billing)
      expect(judgment.frustration.levels).to eq(%w[Calm Angry])
    end
  end

  describe 'decision models in the native v1 listing' do
    subject(:protocol) { RubyLLM::Providers::LMS::ChatCompletions.new(RubyLLM::Providers::LMS.new(config)) }

    def v1_decision
      { 'type' => 'decision', 'key' => 'clef', 'architecture' => 'gemma3', 'decision_type' => 'systemone',
        'has_vision_adapter' => true, 'capabilities' => { 'vision' => true } }
    end

    it 'keeps the decision type even when the model reads images' do
      expect(protocol.normalize_v1_detail(v1_decision)).to include(
        'type' => 'decision', 'decision_type' => 'systemone', 'has_vision_adapter' => true
      )
    end

    it 'lists it as an image-reading judgment model' do
      response = instance_double(Faraday::Response, body: { 'data' => [{ 'id' => 'clef' }] })
      details = { 'clef' => protocol.normalize_v1_detail(v1_decision) }

      listed = protocol.parse_list_models_response(response, 'lms', details: details).first

      expect(listed.modalities.output).to eq(%w[judgment])
      expect(listed.modalities.input).to eq(%w[text image])
      expect(listed.capabilities).to eq(%w[judgment])
      expect(listed.metadata[:decision_type]).to eq('systemone')
    end
  end
end
