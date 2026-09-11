# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::LMS::NativeChat do
  subject(:protocol) { described_class.new(provider) }

  let(:provider) do
    RubyLLM::Providers::LMS.new(
      RubyLLM::Configuration.new.tap { |config| config.lms_api_base = 'http://example.test:1234/v1' }
    )
  end
  let(:model) { instance_double(RubyLLM::Model, id: 'test-model') }

  def user_message(text)
    RubyLLM::Message.new(role: :user, content: text)
  end

  def assistant_message(response_id: nil, body: nil)
    body ||= response_id ? { 'response_id' => response_id } : {}
    RubyLLM::Message.new(role: :assistant, content: 'reply',
                         raw: instance_double(Faraday::Response, body: body))
  end

  it 'talks to the native chat endpoint' do
    expect(protocol.completion_url).to eq('../api/v1/chat')
    expect(protocol.stream_url).to eq(protocol.completion_url)
  end

  describe '#render_payload' do
    it 'renders a plain ask as a string input' do
      payload = protocol.render_payload([user_message('hi')], tools: {}, temperature: 0.5,
                                                              model: model, max_output_tokens: 64)
      expect(payload).to eq(model: 'test-model', input: 'hi', stream: false,
                            temperature: 0.5, max_output_tokens: 64)
    end

    it 'moves system messages into system_prompt' do
      messages = [RubyLLM::Message.new(role: :system, content: 'be brief'), user_message('hi')]
      payload = protocol.render_payload(messages, tools: {}, temperature: nil, model: model)
      expect(payload[:system_prompt]).to eq('be brief')
      expect(payload[:input]).to eq('hi')
    end

    it 'continues a stored conversation from the last response_id' do
      messages = [user_message('first'), assistant_message(response_id: 'resp_ab12'), user_message('second')]
      payload = protocol.render_payload(messages, tools: {}, temperature: nil, model: model)
      expect(payload[:previous_response_id]).to eq('resp_ab12')
      expect(payload[:input]).to eq('second')
    end

    it 'recovers the response_id from raw SSE text after a streamed turn' do
      sse = 'data: {"type":"chat.end","result":{"response_id":"resp_00ff"}}'
      messages = [user_message('first'), assistant_message(body: sse), user_message('second')]
      payload = protocol.render_payload(messages, tools: {}, temperature: nil, model: model)
      expect(payload[:previous_response_id]).to eq('resp_00ff')
    end

    it 'rejects assistant history it cannot continue from' do
      messages = [user_message('first'), assistant_message, user_message('second')]
      expect do
        protocol.render_payload(messages, tools: {}, temperature: nil, model: model)
      end.to raise_error(RubyLLM::Error, /cannot replay assistant history/)
    end

    it 'rejects client-side tools' do
      expect do
        protocol.render_payload([user_message('hi')], tools: { weather: double }, temperature: nil, model: model)
      end.to raise_error(RubyLLM::Error, /does not run client-side tools/)
    end

    it 'rejects structured output schemas' do
      expect do
        protocol.render_payload([user_message('hi')], tools: {}, temperature: nil, model: model,
                                                      schema: { name: 'x', schema: {} })
      end.to raise_error(RubyLLM::Error, /does not support structured output/)
    end
  end

  describe '#resolve_reasoning' do
    it 'omits reasoning when thinking is not configured' do
      expect(protocol.resolve_reasoning(nil)).to be_nil
    end

    it 'maps a thinking effort onto the native setting' do
      expect(protocol.resolve_reasoning(RubyLLM::Thinking::Config.new(effort: :low))).to eq('low')
    end

    it 'turns enabled thinking without an effort on' do
      expect(protocol.resolve_reasoning(RubyLLM::Thinking::Config.new(enabled: true))).to eq('on')
    end

    it 'turns disabled thinking off' do
      expect(protocol.resolve_reasoning(RubyLLM::Thinking::Config.new(enabled: false))).to eq('off')
    end
  end

  describe '#render_input' do
    it 'renders image attachments as data_url parts' do
      attachment = instance_double(RubyLLM::Attachment, type: :image, url?: false,
                                                        for_llm: 'data:image/png;base64,QUJD')
      message = instance_double(RubyLLM::Message, content: 'describe this', attachments: [attachment])
      expect(protocol.render_input([message])).to eq(
        [{ type: 'text', content: 'describe this' },
         { type: 'image', data_url: 'data:image/png;base64,QUJD' }]
      )
    end

    it 'rejects non-image attachments' do
      attachment = instance_double(RubyLLM::Attachment, type: :pdf, mime_type: 'application/pdf')
      message = instance_double(RubyLLM::Message, content: 'read this', attachments: [attachment])
      expect { protocol.render_input([message]) }.to raise_error(RubyLLM::UnsupportedAttachmentError)
    end
  end

  describe '#parse_completion_body' do
    let(:body) do
      {
        'model_instance_id' => 'test-model',
        'output' => [
          { 'type' => 'reasoning', 'content' => 'thinking...' },
          { 'type' => 'message', 'content' => 'Hello!' }
        ],
        'stats' => { 'input_tokens' => 10, 'total_output_tokens' => 7, 'reasoning_output_tokens' => 3 },
        'response_id' => 'resp_ab12'
      }
    end
    let(:raw) { instance_double(Faraday::Response, body: body) }

    it 'builds a message with content, thinking, and stats-backed tokens' do
      message = protocol.parse_completion_body(body, raw: raw)
      expect(message.content).to eq('Hello!')
      expect(message.thinking.text).to eq('thinking...')
      expect(message.tokens.input).to eq(10)
      expect(message.tokens.output).to eq(7)
      expect(message.tokens.thinking).to eq(3)
      expect(message.model).to eq('test-model')
      expect(protocol.response_id_from(message)).to eq('resp_ab12')
    end

    it 'raises the server error message' do
      error_body = { 'error' => { 'message' => 'model not found' } }
      expect do
        protocol.parse_completion_body(error_body, raw: instance_double(Faraday::Response, body: error_body))
      end.to raise_error(RubyLLM::Error, /model not found/)
    end

    it 'raises when there are no output items' do
      expect do
        protocol.parse_completion_body({ 'output' => [] }, raw: raw)
      end.to raise_error(RubyLLM::Error, /no output items/)
    end
  end

  describe '#build_chunk' do
    it 'turns message deltas into content chunks' do
      chunk = protocol.build_chunk('type' => 'message.delta', 'content' => 'Hel')
      expect(chunk.content).to eq('Hel')
    end

    it 'turns reasoning deltas into thinking chunks' do
      chunk = protocol.build_chunk('type' => 'reasoning.delta', 'content' => 'hmm')
      expect(chunk.content).to be_nil
      expect(chunk.thinking.text).to eq('hmm')
    end

    it 'carries stats and the model on the final chunk' do
      chunk = protocol.build_chunk(
        'type' => 'chat.end',
        'result' => { 'model_instance_id' => 'test-model',
                      'stats' => { 'input_tokens' => 5, 'total_output_tokens' => 2 } }
      )
      expect(chunk.model).to eq('test-model')
      expect(chunk.tokens.input).to eq(5)
      expect(chunk.tokens.output).to eq(2)
      expect(chunk.finish_reason).to eq(:stop)
    end

    it 'ignores bookkeeping events' do
      chunk = protocol.build_chunk('type' => 'prompt_processing.progress', 'progress' => 0.5)
      expect(chunk.content).to be_nil
    end
  end

  describe '#parse_streaming_error' do
    it 'extracts the native error message' do
      status, message = protocol.parse_streaming_error('{"error":{"message":"boom"}}')
      expect(status).to eq(500)
      expect(message).to eq('boom')
    end

    it 'passes unparseable data through' do
      expect(protocol.parse_streaming_error('not json').last).to eq('not json')
    end
  end
end
