# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::LMS::ModelManagement do
  # The module only needs a #connection; a bare harness tests it in isolation.
  subject(:provider) do
    harness = Struct.new(:connection) { include RubyLLM::Providers::LMS::ModelManagement }
    harness.new(connection)
  end

  let(:connection) { instance_double(RubyLLM::Providers::LMS::ConnectionGuard) }

  def response_with(body)
    instance_double(Faraday::Response, body: body)
  end

  describe '#native_models' do
    it 'lists the native v1 model catalog' do
      body = { 'models' => [{ 'key' => 'qwen/qwen3-4b', 'loaded_instances' => [] }] }
      allow(connection).to receive(:get).with('../api/v1/models').and_return(response_with(body))
      expect(provider.native_models).to eq(body['models'])
    end

    it 'returns an empty list for an empty catalog' do
      allow(connection).to receive(:get).and_return(response_with({}))
      expect(provider.native_models).to eq([])
    end
  end

  describe '#loaded_models' do
    it 'keeps only models with loaded instances' do
      body = { 'models' => [
        { 'key' => 'loaded-one', 'loaded_instances' => [{ 'instance_id' => 'loaded-one' }] },
        { 'key' => 'cold-one', 'loaded_instances' => [] }
      ] }
      allow(connection).to receive(:get).and_return(response_with(body))
      expect(provider.loaded_models.map { |model| model['key'] }).to eq(['loaded-one'])
    end
  end

  describe '#load_model' do
    it 'posts the model key and compacts absent options away' do
      result = { 'instance_id' => 'qwen/qwen3-4b', 'status' => 'loaded' }
      allow(connection).to receive(:post)
        .with('../api/v1/models/load', { model: 'qwen/qwen3-4b' }, idempotent: false)
        .and_return(response_with(result))
      expect(provider.load_model('qwen/qwen3-4b')).to eq(result)
    end

    it 'passes a context-length override through' do
      allow(connection).to receive(:post)
        .with('../api/v1/models/load', { model: 'qwen/qwen3-4b', context_length: 8192 }, idempotent: false)
        .and_return(response_with({}))
      provider.load_model('qwen/qwen3-4b', context_length: 8192)
      expect(connection).to have_received(:post)
    end
  end

  describe '#unload_model' do
    it 'posts the instance id' do
      allow(connection).to receive(:post)
        .with('../api/v1/models/unload', { instance_id: 'qwen/qwen3-4b:2' }, idempotent: false)
        .and_return(response_with({ 'instance_id' => 'qwen/qwen3-4b:2' }))
      expect(provider.unload_model('qwen/qwen3-4b:2')).to eq('instance_id' => 'qwen/qwen3-4b:2')
    end
  end

  describe '#download_model' do
    it 'posts the model key' do
      allow(connection).to receive(:post)
        .with('../api/v1/models/download', { model: 'qwen/qwen3-4b' }, idempotent: false)
        .and_return(response_with({ 'status' => 'downloading' }))
      expect(provider.download_model('qwen/qwen3-4b')).to eq('status' => 'downloading')
    end
  end

  # Every one of these mutates server state, and RubyLLM's Faraday stack
  # retries POST on a timeout or a dropped connection unless the call opts
  # out. A retried load is not harmless: LM Studio answers a second load of a
  # resident model by starting a second instance, so a slow load that times
  # out would end up holding the weights in memory twice.
  describe 'retry safety' do
    before { allow(connection).to receive(:post).and_return(response_with({})) }

    {
      'load_model' => ['qwen/qwen3-4b'],
      'unload_model' => ['qwen/qwen3-4b:2'],
      'download_model' => ['qwen/qwen3-4b']
    }.each do |method, args|
      it "marks ##{method} non-idempotent so a timeout is not retried" do
        provider.public_send(method, *args)

        expect(connection).to have_received(:post).with(anything, anything, idempotent: false)
      end
    end
  end
end
