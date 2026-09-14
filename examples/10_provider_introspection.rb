#!/usr/bin/env ruby
# frozen_string_literal: true

# The methods that make :lms different from a cloud provider, seen
# through RubyLLM's provider interface:
#
#   local?                      true — model ids are taken on faith
#                               and no API key is ever required
#   configuration_requirements  empty — the gem works with zero config
#   configuration_options       lms_api_base and lms_api_key
#   protocols                   the three dialects LM Studio speaks
#   api_base                    defaults to http://localhost:1234/v1
#   headers                     empty until lms_api_key is set, then
#                               a Bearer token (for auth proxies)
#
#   ruby examples/10_provider_introspection.rb

require_relative 'common'

provider_class = RubyLLM::Provider.resolve!(:lms)
provider = provider_class.new(RubyLLM.config)

protocols = provider_class.protocols.keys.map do |name|
  name == provider_class.default_protocol ? "#{name} (default)" : name.to_s
end

puts <<~CLASS_LEVEL
  == Provider introspection ==

  -- class level --
  display_name:               #{provider_class.display_name}
  local?:                     #{provider_class.local?}
  configuration_options:      #{provider_class.configuration_options.join(', ')}
  configuration_requirements: #{provider_class.configuration_requirements.inspect} (nothing is mandatory)
  protocols:                  #{protocols.join(', ')}

  Set config.lms_protocol to pick one: :responses swaps in the
  /v1/responses dialect, :anthropic swaps in the Messages API at
  /v1/messages, and :native_v0 swaps in LM Studio's own
  /api/v0/chat/completions and its inference stats.

CLASS_LEVEL

with_key = RubyLLM.config.dup
with_key.lms_api_key = 'token-for-an-auth-proxy'

puts <<~INSTANCE_LEVEL
  -- instance level --
  api_base:                #{provider.api_base}
  headers without api key: #{provider.headers.inspect}
  headers with api key:    #{provider_class.new(with_key).headers.inspect}

  Because local? is true, RubyLLM skips registry validation for this
  provider — any model id your LM Studio knows can be used directly.
INSTANCE_LEVEL
