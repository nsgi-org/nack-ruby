# frozen_string_literal: true

require_relative "helper"

describe Nack::Utils do
  it "knows which statuses forbid an entity body" do
    Nack::Utils.no_entity_body?(100).must_equal true
    Nack::Utils.no_entity_body?(199).must_equal true
    Nack::Utils.no_entity_body?(204).must_equal true
    Nack::Utils.no_entity_body?(304).must_equal true
    Nack::Utils.no_entity_body?(200).must_equal false
    Nack::Utils.no_entity_body?(404).must_equal false
  end

  it "returns the first value for a header name" do
    pairs = [["content-type", "text/html"], ["x-a", "1"], ["x-a", "2"]]
    Nack::Utils.get_header(pairs, "content-type").must_equal "text/html"
    Nack::Utils.get_header(pairs, "x-a").must_equal "1"
    Nack::Utils.get_header(pairs, "missing").must_be_nil
  end

  it "replaces all occurrences when setting a header" do
    pairs = [["b", "2"], ["a", "1"], ["b", "3"]]
    Nack::Utils.set_header(pairs, "b", "9")
    pairs.must_equal [["a", "1"], ["b", "9"]]
  end

  it "appends when setting a header not yet present" do
    pairs = [["a", "1"]]
    Nack::Utils.set_header(pairs, "b", "2")
    pairs.must_equal [["a", "1"], ["b", "2"]]
  end

  it "removes all occurrences when deleting a header" do
    pairs = [["a", "1"], ["a", "2"], ["b", "3"]]
    Nack::Utils.delete_header(pairs, "a")
    pairs.must_equal [["b", "3"]]
  end

  it "measures body size in bytes" do
    Nack::Utils.body_size(nil).must_equal 0
    Nack::Utils.body_size("hello").must_equal 5
    Nack::Utils.body_size("héllo").must_equal 6
    Nack::Utils.body_size(IO::Buffer.for("abc")).must_equal 3
  end
end
