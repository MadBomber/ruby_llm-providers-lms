# frozen_string_literal: true

require 'spec_helper'

# Judgments against a real decision model, over both of LM Studio's decision
# endpoints. The wire shapes come from the docs, which are thin -- this is
# what confirms LM Studio answers in the vocabulary the protocols parse.
RSpec.describe 'RubyLLM.judge', :live do # rubocop:disable RSpec/DescribeClass
  include_context 'with configured RubyLLM'

  let(:questions) do
    {
      urgent: { type: :probability, instructions: 'Does this need attention today?' },
      department: { type: :choice, instructions: 'Which team should handle this?',
                    options: { billing: 'Payments and refunds', technical: 'Bugs and integrations',
                               other: 'Everything else' } },
      frustration: { type: :score, instructions: 'How frustrated is the customer?',
                     levels: %w[Calm Frustrated Angry] }
    }
  end

  let(:ticket) { 'I was charged twice and I am furious. Refund the duplicate charge today!' }

  each_model(JUDGMENT_MODELS) do |provider, model, model_info|
    %i[decisions system_one].each do |endpoint|
      it "#{provider}/#{model} judges all three question types over #{endpoint}" do
        judgment = RubyLLM.context { |config| config.lms_judgment_protocol = endpoint }
                          .judge(ticket, questions: questions, model: model, provider: provider,
                                         assume_model_exists: true)

        expect(judgment.urgent.probability).to be > 0.5
        expect(judgment.department.choice).to eq(:billing)
        expect(judgment.department.probabilities.keys).to contain_exactly(:billing, :technical, :other)
        expect(judgment.frustration.score).to be_between(0, 2)
      end
    end

    it "#{provider}/#{model} is listed as a judgment model" do
      listed = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config).list_models.find { |m| m.id == model }

      expect(listed.modalities.output).to eq(%w[judgment])
    end

    next unless model_info[:vision]

    %i[decisions system_one].each do |endpoint|
      it "#{provider}/#{model} judges an image over #{endpoint}" do
        image = File.expand_path('../fixtures/red_square.png', __dir__)

        judgment = RubyLLM.context { |config| config.lms_judgment_protocol = endpoint }
                          .judge(questions: { red: { type: :probability, instructions: 'Is the image red?' } },
                                 with: image, model: model, provider: provider, assume_model_exists: true)

        expect(judgment.red.probability).to be > 0.5
      end
    end
  end
end
