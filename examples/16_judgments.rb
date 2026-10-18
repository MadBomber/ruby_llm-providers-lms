#!/usr/bin/env ruby
# frozen_string_literal: true

# Judgments: asking a decision model typed questions instead of chatting.
#
# A decision model doesn't write text. It reads the input once and answers
# every question with numbers: the chance something is true, a probability
# for each option in a fixed set, or a position on an ordered scale. There is
# no output to parse and no format to coax, and it answers in milliseconds.
#
# RubyLLM 2.1 calls this a judgment. This demo asks the three kinds of
# question in one call and prints everything that comes back.
#
#   ruby examples/16_judgments.rb
#
# Needs a decision model (see DECISION_MODEL in common.rb).

require_relative 'common'

REVIEW = <<~TEXT
  The blender arrived two days late, which was annoying. But it crushes ice in
  seconds, it is quiet, and smoothies come out perfectly smooth. Best kitchen
  purchase this year.
TEXT

QUESTIONS = {
  # probability: the chance the answer is yes. (Optional criteria can say
  # what counts as yes and no; example 18 shows why to test them per endpoint.)
  satisfied: { type: :probability, instructions: 'Is the customer satisfied with the product?' },
  late: { type: :probability, instructions: 'Is the customer complaining about delivery?' },
  # choice: one option from a fixed set, with a probability for every option.
  topic: {
    type: :choice,
    instructions: 'What is the review mostly about?',
    options: { shipping: 'Delivery speed or damage in transit', quality: 'How well the product works',
               support: 'Dealing with customer service', price: 'Cost or value for money' }
  },
  # score: a position on ordered levels, which can fall between them.
  sentiment: {
    type: :score,
    instructions: 'Overall, how does the customer feel about the product?',
    levels: %w[Furious Unhappy Mixed Happy Delighted]
  }
}.freeze

PROBABILITY_ROW = '%-10s probability %.3f  %s'
CHOICE_ROW = '%-10s choice      %s (confidence %.2f)'
SCORE_ROW = '%-10s score       %.2f of 0..%d, nearest "%s" (confidence %.2f)'
DISTRIBUTION_ROW = '%14s %-10s %.3f  %s'

def bar(probability, width: 30)
  '#' * (probability * width).round
end

def show_probability(name, answer)
  puts format(PROBABILITY_ROW, name, answer.probability, bar(answer.probability))
end

def show_choice(name, answer)
  puts format(CHOICE_ROW, name, answer.choice, answer.confidence)
  answer.probabilities.each { |option, p| puts format(DISTRIBUTION_ROW, '', option, p, bar(p)) }
end

def show_score(name, answer)
  level = answer.levels[answer.score.round]
  puts format(SCORE_ROW, name, answer.score, answer.levels.length - 1, level, answer.confidence)
  answer.probabilities.each do |index, p|
    puts format(DISTRIBUTION_ROW, '', answer.levels[index], p, bar(p))
  end
end

puts <<~INTRO
  == Judgments with #{DECISION_MODEL} ==

  Input:
  #{REVIEW.gsub(/^/, '  ')}
INTRO

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
judgment = RubyLLM.judge(REVIEW, questions: QUESTIONS, model: DECISION_MODEL, provider: :lms)
elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

# Answers are readers named after the questions; each is a RubyLLM::Probability,
# RubyLLM::Choice or RubyLLM::Score.
judgment.each do |name, answer|
  case answer
  when RubyLLM::Probability then show_probability(name, answer)
  when RubyLLM::Choice then show_choice(name, answer)
  when RubyLLM::Score then show_score(name, answer)
  end
end

puts <<~SUMMARY

  -- the judgment itself --
  model:         #{judgment.model}
  input tokens:  #{judgment.tokens.input}
  output tokens: #{judgment.tokens.output} (a decision model writes nothing)
  round trip:    #{(elapsed * 1000).round} ms (the first call includes loading the model)

  judgment.to_h gives the whole thing as plain data, ready to store:
  #{judgment.to_h[:answers].transform_values { |h| h.slice(:probability, :choice, :score) }.inspect}
SUMMARY
