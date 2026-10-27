# frozen_string_literal: true

# NACK_BENCH_SUBJECT=table NACK_BENCH_SHARED=1 ruby -r<ruby-bench>/harness/ractor bench/ractor/throughput.rb

require_relative "subject"

CALL_COUNT = 100_000
LOOKUP_COUNT = 10_000_000
MATCH_COUNT = 1_000_000

run_benchmark(5) do
  # Building in each Ractor is left in, as its share of the time is negligible.
  subject = Bench.subject
  case Bench::SUBJECT
  when "chain" then CALL_COUNT.times { subject.call }
  when "table"
    keys = Bench.keys(Bench::TABLE_SIZE)
    LOOKUP_COUNT.times { |i| subject.include?(keys[i % keys.size]) }
  when "regexp" then MATCH_COUNT.times { subject.match?(Bench::TEXT) }
  else raise ArgumentError, "NACK_BENCH_SUBJECT must be chain, table or regexp"
  end
end
