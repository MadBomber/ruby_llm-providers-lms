# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::LMS::ConnectionGuard do
  subject(:guard) { described_class.new(connection) }

  let(:provider) { instance_double(RubyLLM::Providers::LMS, api_base: 'http://localhost:1234/v1') }
  let(:connection) { instance_double(RubyLLM::Transport::Connection, provider: provider) }

  { get: ['models'], post: ['chat/completions', {}], patch: ['models', {}], delete: ['models'] }.each do |verb, args|
    it "wraps a connection failure on ##{verb} in a RubyLLM::Error" do
      allow(connection).to receive(verb).and_raise(Faraday::ConnectionFailed, 'Connection refused')

      expect { guard.public_send(verb, *args) }.to raise_error(RubyLLM::Error) do |error|
        expect(error.message).to include('http://localhost:1234/v1')
        expect(error.message).to include('lms server start')
        expect(error.cause).to be_a(Faraday::ConnectionFailed)
      end
    end
  end

  it 'passes successful calls through with arguments and block' do
    response = instance_double(Faraday::Response)
    request = Object.new
    allow(connection).to receive(:post).with('chat/completions', { model: 'x' }, usage: nil)
                                       .and_yield(request).and_return(response)

    yielded = nil
    result = guard.post('chat/completions', { model: 'x' }, usage: nil) { |req| yielded = req }

    expect(result).to be(response)
    expect(yielded).to be(request)
  end

  it 'lets other errors propagate untouched' do
    allow(connection).to receive(:get).and_raise(RubyLLM::UnauthorizedError.new('nope'))

    expect { guard.get('models') }.to raise_error(RubyLLM::UnauthorizedError, 'nope')
  end

  it 'names the server address and the start command in its message' do
    expect(guard.unreachable_message)
      .to eq('Cannot connect to the LM Studio server at http://localhost:1234/v1. ' \
             'Start it with `lms server start`.')
  end
end
