#!/usr/bin/env ruby
# frozen_string_literal: true

# Decision model first, chat model only when needed.
#
# A decision model answers in tens of milliseconds and writes nothing; a chat
# model takes seconds to write a reply. Putting the first in front of the
# second means the expensive model only sees the messages that deserve it.
# Here a decision model screens a contact-form inbox (spam? needs a reply?
# what kind?) and the chat model drafts replies for just the ones that pass.
#
#   ruby examples/20_judge_then_chat.rb
#
# Needs a decision model (DECISION_MODEL) and a chat model (MODEL), both
# from common.rb; LM Studio loads each on first use.

require_relative 'common'

# The screen: is it spam, does it need an answer, and what kind is it.
class ContactScreen < RubyLLM::Judge
  model DECISION_MODEL, provider: :lms

  # Short, plain questions work best on small decision models; wordier ones
  # that pack in several conditions blurred the answers when this was tuned.
  probability :spam, 'Is this message spam?'
  probability :needs_reply, 'Does this message need a response from our team?'

  choice :kind, 'What kind of message is this?' do
    question 'Asking how something works or whether we offer it'
    complaint 'Reporting a problem or unhappy with something'
    praise 'Saying thanks or something positive'
    other 'Anything else'
  end
end

INBOX = [
  'Do you ship to Canada, and if so how long does delivery usually take?',
  'CONGRATULATIONS!!! You have been selected for a $500 gift card. Click here to claim now.',
  'Just wanted to say the new dashboard is fantastic. Great work, team!',
  'My order #4417 arrived with a broken handle. What should I do?',
  'We offer premium SEO backlinks at unbeatable prices. Reply for our rate card.'
].freeze

SPAM = 0.5
REPLY = 0.6

ROW = '%-6s spam %.2f  reply %.2f  %-9s %s'

def seconds_since(started)
  Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
end

# Returns the action for a screened message: :drop, :file or :reply.
def triage(judgment)
  return :drop if judgment.spam.probability >= SPAM
  return :reply if judgment.needs_reply.probability >= REPLY

  :file
end

def draft_reply(message, kind)
  new_chat.with_instructions(<<~PROMPT).ask(message).content.strip
    You answer a small online shop's contact form. The message is a #{kind}.
    Write a short, friendly reply of two sentences at most. Do not invent
    order details, prices or policies; offer to follow up instead.
  PROMPT
end

puts <<~INTRO
  == Screen with #{DECISION_MODEL}, reply with #{MODEL} ==

INTRO

ContactScreen.judge('warm up') # load the decision model so the timings below are fair

screen_time = 0.0
to_reply = INBOX.filter_map do |message|
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  judgment = ContactScreen.judge(message)
  screen_time += seconds_since(started)

  action = triage(judgment)
  puts format(ROW, action, judgment.spam.probability,
              judgment.needs_reply.probability, judgment.kind.choice, message[0, 60])
  [message, judgment.kind.choice] if action == :reply
end

puts <<~SCREENED

  Screened #{INBOX.length} messages in #{(screen_time * 1000).round} ms. #{to_reply.length} need a reply.

SCREENED

started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
to_reply.each do |message, kind|
  puts <<~DRAFT
    > #{message}
    #{draft_reply(message, kind)}

  DRAFT
end
reply_time = seconds_since(started)

puts <<~SUMMARY
  -- reading this --
  screening #{INBOX.length} messages: #{(screen_time * 1000).round} ms with the decision model
  drafting #{to_reply.length} replies:   #{reply_time.round(1)} s with the chat model (including any load time)

  Without the screen, every message, spam included, would have gone to the
  chat model. The judgment's choice (#{to_reply.map(&:last).uniq.join(', ')}) also rides into the
  prompt, so the chat model knows what it is answering.
SUMMARY
