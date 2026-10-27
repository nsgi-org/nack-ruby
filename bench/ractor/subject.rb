# frozen_string_literal: true

require_relative "../objects"

module Bench
  SUBJECT = ENV.fetch("NACK_BENCH_SUBJECT").freeze
  CHAIN_LENGTH = Integer(ENV.fetch("NACK_BENCH_CHAIN_LENGTH", 32))
  TABLE_SIZE = Integer(ENV.fetch("NACK_BENCH_TABLE_SIZE", 10_000))

  def self.build
    case SUBJECT
    when "none" then nil
    when "chain" then chain(CHAIN_LENGTH)
    when "table" then table(TABLE_SIZE)
    when "regexp" then regexp
    else raise ArgumentError, "NACK_BENCH_SUBJECT must be none, chain, table or regexp"
    end
  end

  SHARED_SUBJECT = (Ractor.make_shareable(build) if ENV["NACK_BENCH_SHARED"] == "1")

  def self.subject
    SHARED_SUBJECT || build
  end
end
