#!/usr/bin/env ruby
# frozen_string_literal: true

# Embeddings: LM Studio serves embedding models through the same
# OpenAI-compatible endpoint, so `RubyLLM.embed` works locally —
# handy for RAG and semantic search with no data leaving the machine.
#
#   ruby examples/05_embeddings.rb

require_relative 'common'

EMBEDDING_MODEL = ENV.fetch('LMS_EMBEDDING_MODEL', 'text-embedding-nomic-embed-text-v1.5')

def embed(texts)
  RubyLLM.embed(texts, model: EMBEDDING_MODEL, provider: :lms)
end

def cosine_similarity(vec_a, vec_b)
  dot = vec_a.zip(vec_b).sum { |a, b| a * b }
  dot / (Math.sqrt(vec_a.sum { |v| v * v }) * Math.sqrt(vec_b.sum { |v| v * v }))
end

puts <<~INTRO
  == Embeddings (#{EMBEDDING_MODEL}) ==

INTRO

single = embed("Ruby is a programmer's best friend")
puts "one text  -> vector of #{single.vectors.length} dimensions"

sentences = [
  'The cat sat on the mat.',
  'A kitten was resting on the rug.',
  'Quarterly revenue grew by twelve percent.'
]
batch = embed(sentences)
puts "batch     -> #{batch.vectors.length} vectors\n\n"

base = batch.vectors.first
puts 'similarity to first sentence:'
sentences.each_with_index do |sentence, index|
  score = cosine_similarity(base, batch.vectors[index])
  puts format('  %<score>.4f  %<sentence>s', score:, sentence:)
end
