# frozen_string_literal: true

require 'spec_helper'

RSpec.describe RubyLLM::Chat, :live do
  include_context 'with configured RubyLLM'

  let(:weather_tool) do
    Class.new(RubyLLM::Tool) do
      description 'Gets current weather for a location'
      parameter :latitude, description: 'Latitude'
      parameter :longitude, description: 'Longitude'

      def execute(latitude:, longitude:)
        "Current weather at #{latitude}, #{longitude}: 15°C, Wind: 10 km/h"
      end
    end
  end

  each_model(TOOL_MODELS) do |provider, model|
    it "#{provider}/#{model} can use tools" do
      chat = RubyLLM.chat(model: model, provider: provider, assume_model_exists: true).with_tools(weather_tool)
      response = chat.ask("What's the weather in Berlin? Use 52.5200, 13.4050.")

      expect(response.content).to include('15')
      expect(response.content).to include('10')
      expect(chat.messages.any?(&:tool_call?)).to be(true)
    end

    # LM Studio accepts tool_choice ("auto" / "none" / "required") for every
    # model it serves, which is what the catalog capability describes.
    it "#{provider}/#{model} declares tool choice in the live listing" do
      listed = RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config).list_models.find { |m| m.id == model }

      expect(listed.supports?(:function_calling)).to be(true)
      expect(listed.supports?(:tool_choice)).to be(true)
    end
  end

  each_model(TOOL_CHOICE_MODELS) do |provider, model|
    it "#{provider}/#{model} honours a forced tool choice" do
      chat = RubyLLM.chat(model: model, provider: provider, assume_model_exists: true)
                    .with_tools(weather_tool)
                    .with_tool_options(choice: :required)
      chat.ask('Say hello. Use 52.5200, 13.4050 if you need coordinates.')

      expect(chat.messages.any?(&:tool_call?)).to be(true)
    end
  end
end
