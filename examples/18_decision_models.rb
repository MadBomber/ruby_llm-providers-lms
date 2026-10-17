#!/usr/bin/env ruby
# frozen_string_literal: true

# Which decision models do you have, and which endpoint should you use?
#
# 1. Lists the decision models LM Studio recognizes on this machine.
# 2. Asks every one of them the same questions over both decision endpoints,
#    /v1/decisions and /v1/systemone, with timings.
# 3. Shows where the endpoints differ most: probability criteria.
# 4. Shows what happens when you point a judgment at a chat model.
#
#   ruby examples/18_decision_models.rb
#
# It runs every decision model you have downloaded, so the first pass loads
# each one into memory. Clef Flash alone is about 7 GB.

require_relative 'common'

ENDPOINTS = %i[decisions system_one].freeze

TICKET = 'My invoice shows a charge for a plan I cancelled last month. Please fix this before Friday.'

QUESTIONS = {
  urgent: { type: :probability, instructions: 'Does this need attention this week?' },
  team: { type: :choice, instructions: 'Which team should handle this?',
          options: { billing: 'Charges and refunds', technical: 'Bugs and outages', sales: 'Plans and pricing' } },
  mood: { type: :score, instructions: 'How upset is the customer?', levels: %w[Calm Annoyed Angry] }
}.freeze

# Decisions has no field for probability criteria, so RubyLLM folds them into
# the instruction text; System One sends them as structured criteria. Small
# models can read the two very differently.
CRITERIA_QUESTION = {
  recommend: { type: :probability, instructions: 'Would this customer recommend the product to a friend?',
               criteria: { yes: 'Ends satisfied with the product itself', no: 'Would steer others away' } }
}.freeze

MIXED_REVIEW = 'The blender arrived late and the lid was cracked. Support sent a replacement ' \
               'within a day and it works great now. Still annoyed about the wait.'

CATALOG_HEADER = 'ID               DECISION TYPE  PARAMS   SIZE     IMAGES  NAME'
CATALOG_ROW = '%-16s %-14s %-8s %-8s %-7s %s'
JUDGMENT_HEADER = 'MODEL            ENDPOINT    URGENT TEAM        CONF  MOOD    TIME'
JUDGMENT_ROW = '%-16s %-11s %6.2f %-10s %5.2f %5.2f %5d ms'
CRITERIA_HEADER = 'MODEL              decisions  system_one'
CRITERIA_ROW = '%-16s %11.3f %11.3f'
GIGABYTES = '%.1f GB'

def decision_models
  RubyLLM::Provider.resolve!(:lms).new(RubyLLM.config).list_models
                   .select { |model| model.capabilities.include?('judgment') }
end

def gigabytes(bytes)
  bytes ? format(GIGABYTES, bytes / 1e9) : '?'
end

# Returns [judgment, milliseconds].
def timed_judgment(input, questions, model, endpoint)
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  judgment = RubyLLM.judge(input, questions:, model:, provider: :lms, context: judgment_context(endpoint))
  [judgment, ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round]
end

models = decision_models
abort 'No decision models found. See DECISION_MODEL in examples/common.rb for some to download.' if models.empty?

puts <<~HEADER
  == 1. Decision models LM Studio recognizes (#{models.length}) ==

  #{CATALOG_HEADER}
HEADER
models.each do |model|
  puts format(CATALOG_ROW, model.id, model.metadata[:decision_type],
              model.metadata[:params_string], gigabytes(model.metadata[:size_bytes]),
              model.modalities.input.include?('image') ? 'yes' : 'no', model.name)
end

puts <<~HEADER

  == 2. Same questions, every model, both endpoints ==

  Ticket: #{TICKET}

  #{JUDGMENT_HEADER}
HEADER

models.each do |model|
  timed_judgment(TICKET, QUESTIONS, model.id, :decisions) # warm up: load the model before timing
  ENDPOINTS.each do |endpoint|
    judgment, ms = timed_judgment(TICKET, QUESTIONS, model.id, endpoint)
    puts format(JUDGMENT_ROW, model.id, endpoint, judgment.urgent.probability,
                judgment.team.choice, judgment.team.confidence, judgment.mood.score, ms)
  end
end

puts <<~HEADER

  == 3. Probability criteria, per endpoint ==

  Review: #{MIXED_REVIEW}
  Question: #{CRITERIA_QUESTION[:recommend][:instructions]}
            yes = #{CRITERIA_QUESTION[:recommend][:criteria][:yes]}
            no  = #{CRITERIA_QUESTION[:recommend][:criteria][:no]}

  #{CRITERIA_HEADER}
HEADER

models.each do |model|
  answers = ENDPOINTS.map do |endpoint|
    timed_judgment(MIXED_REVIEW, CRITERIA_QUESTION, model.id, endpoint).first.recommend.probability
  end
  puts format(CRITERIA_ROW, model.id, *answers)
end

puts <<~HEADER

  == 4. A chat model is not a decision model ==

HEADER

begin
  RubyLLM.judge(TICKET, questions: QUESTIONS, model: MODEL, provider: :lms)
rescue RubyLLM::Error => e
  puts "#{MODEL}: #{e.class}"
  puts "  #{e.message}"
end

puts <<~SUMMARY

  -- reading this --
  Both endpoints take the same questions and the same models, but they phrase
  them to the model differently, and the smallest models notice: compare a
  600M model's confidence and criteria answers across the two rows. Larger
  models mostly agree with themselves. So pick the endpoint first (the default
  is :decisions), then tune your questions and thresholds on that endpoint;
  numbers tuned on one don't carry over to the other unchanged. Guidance in
  the question text itself reaches the model the same way on both.
SUMMARY
