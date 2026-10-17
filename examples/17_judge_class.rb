#!/usr/bin/env ruby
# frozen_string_literal: true

# A reusable judge: declare the questions once in a RubyLLM::Judge subclass,
# then run it over every incoming record.
#
# This is the shape most applications want. The class is the policy (what
# to ask, which options exist); the thresholds that act on the answers stay
# in plain Ruby, where they are easy to test and tune. The demo triages a
# small support inbox and routes each ticket.
#
#   ruby examples/17_judge_class.rb
#
# Needs a decision model (see DECISION_MODEL in common.rb).

require_relative 'common'

# Three questions about one support ticket, sent in a single request.
class TicketTriage < RubyLLM::Judge
  model DECISION_MODEL, provider: :lms

  # The teams change at runtime, so they are an input rather than a constant:
  # TicketTriage.judge(ticket, teams: {...}) supplies them per call, and the
  # lambda below reads them when the question resolves.
  inputs :teams

  probability :urgent, 'Does this need attention today?'

  choice :team, 'Which team should handle this?', -> { teams }

  score :frustration, 'How frustrated is the customer?', %w[Calm Annoyed Frustrated Angry]
end

TEAMS = {
  billing: 'Charges, refunds, invoices and payment methods',
  technical: 'Bugs, errors, outages and integrations',
  accounts: 'Logins, passwords and account settings',
  sales: 'Pricing questions, plans and upgrades'
}.freeze

INBOX = [
  'You charged my card twice this month. I want the duplicate refunded today.',
  'The API has returned 500 errors for an hour and our checkout is down!!!',
  'How much would it cost to move our team of 40 to the enterprise plan?',
  'I forgot my password and the reset email never arrives. Third time asking.',
  'Small thing: the export button tooltip has a typo. No rush at all.'
].freeze

URGENT = 0.7
ANGRY = 2.0 # Frustrated or worse on the 0..3 scale
UNSURE = 0.5 # below this team confidence, a person should look

# Plain Ruby on top of the judgment: easy to unit-test, easy to change.
def route(judgment)
  return 'escalate to on-call lead' if judgment.urgent.probability >= URGENT && judgment.frustration.score >= ANGRY
  return 'human triage (team unclear)' if judgment.team.confidence < UNSURE
  return "#{judgment.team.choice} queue, priority" if judgment.urgent.probability >= URGENT

  "#{judgment.team.choice} queue"
end

HEADER = 'TICKET                                         URGENT TEAM        CONF FRUSTR  ROUTE'
ROW = '%-46s %6.2f %-10s %5.2f %6.1f  %s'

puts <<~INTRO
  == Ticket triage with a RubyLLM::Judge subclass (#{DECISION_MODEL}) ==

  #{HEADER}
INTRO

INBOX.each do |ticket|
  judgment = TicketTriage.judge(ticket, teams: TEAMS)
  puts format(ROW, "#{ticket[0, 43]}...", judgment.urgent.probability, judgment.team.choice,
              judgment.team.confidence, judgment.frustration.score, route(judgment))
end

puts <<~SUMMARY

  -- reading this --
  URGENT  probability the ticket needs attention today (route at >= #{URGENT})
  CONF    how sure the model is of TEAM; under #{UNSURE} goes to a person
  FRUSTR  0 Calm .. 3 Angry; can fall between levels

  Each ticket is one request, and every question in the class rides along in
  it. Adding a question costs input tokens, not another round trip.
SUMMARY
