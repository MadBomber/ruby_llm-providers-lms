# frozen_string_literal: true

# Model matrices for the live contract specs. LM Studio serves whatever
# models are downloaded on this machine, so these ids are machine-specific;
# swap in ids from `lms ls` (or models.json) when recording cassettes.
# See RubyLLM's full live matrix and specs: https://github.com/crmne/ruby_llm/tree/main/spec
PROVIDER = :lms
CHAT_MODELS = [
  { provider: PROVIDER, model: 'openai/gpt-oss-20b' }
].freeze
TOOL_MODELS = CHAT_MODELS
# gpt-oss models mangle json_schema values on LM Studio (harmony format);
# qwen3 models honor it.
STRUCTURED_OUTPUT_MODELS = [
  { provider: PROVIDER, model: 'qwen3-0.6b-bible-assistant' }
].freeze

EMBEDDING_MODELS = [
  { provider: PROVIDER, model: 'text-embedding-nomic-embed-text-v1.5' }
].freeze
IMAGE_GENERATION_MODELS = [].freeze
SPEECH_MODELS = [].freeze
VIDEO_GENERATION_MODELS = [].freeze
MODERATION_MODELS = [].freeze
RERANK_MODELS = [].freeze

def each_model(models)
  models.each { |model_info| yield model_info[:provider], model_info[:model], model_info }
end
