# frozen_string_literal: true

module RubyLLM
  module Providers
    # Version of the ruby_llm-providers-lms gem. Kept in its own file so the
    # gemspec can read the literal without loading the provider.
    class LMS < Provider
      VERSION = '0.2.0'

      def self.version
        VERSION
      end
    end
  end
end
