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
# Forcing a call with tool_choice: "required". LM Studio forwards the setting
# for any model, but whether the weights obey it is a model trait -- gpt-oss
# ignores it on the harmony format, the way it ignores json_schema values.
TOOL_CHOICE_MODELS = [
  { provider: PROVIDER, model: 'qwen/qwen3.8-27b' }
].freeze
# gpt-oss models mangle json_schema values on LM Studio (harmony format);
# qwen3 models honor it.
STRUCTURED_OUTPUT_MODELS = [
  { provider: PROVIDER, model: 'qwen3-0.6b-bible-assistant' }
].freeze

# Reasoning over the OpenAI-compatible endpoint (reasoning_effort in,
# reasoning_content out). Needs a model whose listing reports reasoning
# options -- `lms ls` or models.json shows which.
REASONING_MODELS = [
  { provider: PROVIDER, model: 'openai/gpt-oss-20b' }
].freeze

# Turning reasoning off needs a model whose listing reports LM Studio's
# 'off' option. gpt-oss reports only low/medium/high and really cannot stop,
# so with_thinking(false) rightly refuses for it.
REASONING_OFF_MODELS = [
  { provider: PROVIDER, model: 'qwen/qwen3.8-27b' }
].freeze

# Image input. Needs a model LM Studio flags `vision: true`.
VISION_MODELS = [
  { provider: PROVIDER, model: 'qwen/qwen3.8-27b' }
].freeze

EMBEDDING_MODELS = [
  { provider: PROVIDER, model: 'text-embedding-nomic-embed-text-v1.5' }
].freeze

# The native /api/v1/chat protocol (protocol: :native_chat). The reasoning
# matrix needs a model that emits reasoning items (gpt-oss does; most
# instruct fine-tunes do not); the management model should be small so
# load/unload cycles stay fast.
NATIVE_CHAT_MODELS = [
  { provider: PROVIDER, model: 'qwen3-0.6b-bible-assistant' }
].freeze
NATIVE_REASONING_MODELS = [
  { provider: PROVIDER, model: 'openai/gpt-oss-20b' }
].freeze

MANAGEMENT_MODEL = 'qwen3-0.6b-bible-assistant'
IMAGE_GENERATION_MODELS = [].freeze
SPEECH_MODELS = [].freeze
VIDEO_GENERATION_MODELS = [].freeze
MODERATION_MODELS = [].freeze
RERANK_MODELS = [].freeze

def each_model(models)
  models.each { |model_info| yield model_info[:provider], model_info[:model], model_info }
end
