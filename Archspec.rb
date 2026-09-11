# frozen_string_literal: true

source 'lib/**/*.rb'

component :provider,
          in: %w[
            lib/ruby_llm/providers/lms.rb
            lib/ruby_llm/providers/lms/**/*.rb
          ],
          namespace: 'RubyLLM::Providers::LMS'

provider.cannot_reference_constants 'RSpec', 'WebMock', 'VCR'

preset :ruby_conventions
