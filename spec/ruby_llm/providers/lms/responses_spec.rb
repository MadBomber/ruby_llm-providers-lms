# frozen_string_literal: true

require 'spec_helper'

# OpenAI's Responses API never returns raw reasoning, only an optional
# summary, so RubyLLM's stock protocol reads a reasoning item's `summary`.
# LM Studio runs the model locally and returns the reasoning itself, in
# `content` as `reasoning_text`, leaving `summary` empty — and streams it
# under a different event name. Reading only OpenAI's shape loses the
# reasoning on both paths: the response spends reasoning tokens and
# `message.thinking` comes back nil.
RSpec.describe RubyLLM::Providers::LMS::Responses do
  subject(:protocol) { described_class.new(provider) }

  let(:provider) do
    RubyLLM::Providers::LMS.new(
      RubyLLM::Configuration.new.tap { |config| config.lms_api_base = 'http://example.test:1234/v1' }
    )
  end

  describe '#parse_reasoning_summary' do
    it "reads the reasoning text out of LM Studio's content items" do
      output = [
        { 'type' => 'reasoning', 'summary' => [],
          'content' => [{ 'type' => 'reasoning_text', 'text' => 'Simple arithmetic: 4.' }] },
        { 'type' => 'message', 'content' => [{ 'type' => 'output_text', 'text' => '4' }] }
      ]

      expect(protocol.parse_reasoning_summary(output)).to eq('Simple arithmetic: 4.')
    end

    it "still prefers OpenAI's summary when one is present" do
      output = [{ 'type' => 'reasoning',
                  'summary' => [{ 'type' => 'summary_text', 'text' => 'summarized' }],
                  'content' => [{ 'type' => 'reasoning_text', 'text' => 'verbatim' }] }]

      expect(protocol.parse_reasoning_summary(output)).to eq('summarized')
    end

    it 'joins reasoning split across several items' do
      output = [
        { 'type' => 'reasoning', 'content' => [{ 'type' => 'reasoning_text', 'text' => 'first' }] },
        { 'type' => 'reasoning', 'content' => [{ 'type' => 'reasoning_text', 'text' => 'second' }] }
      ]

      expect(protocol.parse_reasoning_summary(output)).to eq("first\nsecond")
    end

    it 'ignores content parts that are not reasoning text' do
      output = [{ 'type' => 'reasoning', 'content' => [{ 'type' => 'other', 'text' => 'nope' }] }]

      expect(protocol.parse_reasoning_summary(output)).to be_nil
    end

    it 'reports no reasoning when the response carries none' do
      output = [{ 'type' => 'message', 'content' => [{ 'type' => 'output_text', 'text' => '4' }] }]

      expect(protocol.parse_reasoning_summary(output)).to be_nil
    end
  end

  describe '#build_chunk' do
    it "turns LM Studio's reasoning deltas into thinking chunks" do
      chunk = protocol.build_chunk('type' => 'response.reasoning_text.delta', 'delta' => 'The user')

      expect(chunk.thinking.text).to eq('The user')
      expect(chunk.content).to be_nil
    end

    it 'leaves every other event to the stock protocol' do
      chunk = protocol.build_chunk('type' => 'response.output_text.delta', 'delta' => '4')

      expect(chunk.content).to eq('4')
      expect(chunk.thinking).to be_nil
    end
  end
end
