# frozen_string_literal: true

require 'delegate'

module RubyLLM
  module Providers
    class LMS < Provider
      # Wraps the transport connection so a request against a server that
      # is not running surfaces as a RubyLLM::Error explaining how to start
      # LM Studio, instead of a raw Faraday::ConnectionFailed.
      class ConnectionGuard < SimpleDelegator
        %i[get post patch delete].each do |verb|
          define_method(verb) do |*args, **kwargs, &block|
            __getobj__.public_send(verb, *args, **kwargs, &block)
          rescue Faraday::ConnectionFailed
            raise Error, unreachable_message
          end
        end

        def unreachable_message
          "Cannot connect to the LM Studio server at #{provider.api_base}. " \
            'Start it with `lms server start`.'
        end
      end
    end
  end
end
