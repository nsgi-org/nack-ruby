# frozen_string_literal: true

# NACK_BENCH_SUBJECT=table NACK_BENCH_SHARED=1 ruby -r<ruby-bench>/harness/ractor bench/ractor/memory.rb

require_relative "subject"

run_benchmark(5, scenario: true) do |ractor_count|
  port = Ractor::Port.new
  ractors = Array.new(ractor_count) do
    Ractor.new(port) do |port|
      # A shared subject is built at load, before the harness reads its base RSS, so only what each Ractor adds counts.
      subject = Bench.subject
      port << :ready
      Ractor.receive
      subject
    end
  end
  ractor_count.times { port.receive }
  proc { ractors.each { |ractor| ractor.send(:stop) }.each(&:join) }
end
