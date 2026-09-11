# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Providers::LMS::ModelManagement, :live do
  include_context 'with configured RubyLLM'

  let(:provider) { RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config) }

  it 'lms lists the native model catalog with rich details' do
    models = provider.native_models

    expect(models).not_to be_empty
    expect(models.first).to include('key', 'type', 'capabilities')
  end

  it 'lms loads and unloads a model' do
    loaded = provider.load_model(MANAGEMENT_MODEL)
    expect(loaded['status']).to eq('loaded')
    expect(loaded['instance_id']).not_to be_nil

    unloaded = provider.unload_model(loaded['instance_id'])
    expect(unloaded['instance_id']).to eq(loaded['instance_id'])
  end
end
