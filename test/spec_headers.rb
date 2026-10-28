# frozen_string_literal: true

require_relative "helper"

describe Nack::Headers do
  it "returns the first value of a name" do
    headers = Nack::Headers.new([["a", "1"], ["b", "2"], ["a", "3"]])
    headers["a"].must_equal "1"
    headers["c"].must_be_nil
  end

  it "returns every value of a name" do
    headers = Nack::Headers.new([["a", "1"], ["b", "2"], ["a", "3"]])
    headers.get_all("a").must_equal ["1", "3"]
    headers.get_all("c").must_equal []
  end

  it "appends a field when setting a name not yet present" do
    headers = Nack::Headers.new([["a", "1"], ["b", "2"], ["a", "3"]])
    headers["c"] = "4"
    headers.to_a.must_equal [["a", "1"], ["b", "2"], ["a", "3"], ["c", "4"]]
  end

  it "replaces every field of a name with one" do
    headers = Nack::Headers.new([["a", "1"], ["b", "2"], ["a", "3"]])
    headers["a"] = "4"
    headers.to_a.must_equal [["a", "4"], ["b", "2"]]
  end

  it "appends a field even if its name is present" do
    headers = Nack::Headers.new([["a", "1"], ["b", "2"], ["a", "3"]])
    headers.add("a", "4").must_be_same_as headers
    headers.to_a.must_equal [["a", "1"], ["b", "2"], ["a", "3"], ["a", "4"]]
  end

  it "raises SpecError on an invalid name or value" do
    headers = Nack::Headers.new([["a", "1"], ["b", "2"], ["a", "3"]])
    -> { headers.add("A", "4") }.must_raise Nack::SpecError
    -> { headers["a"] = "4\n" }.must_raise Nack::SpecError
    headers.to_a.must_equal [["a", "1"], ["b", "2"], ["a", "3"]]
  end

  it "deletes every field of a name" do
    headers = Nack::Headers.new([["a", "1"], ["b", "2"], ["a", "3"]])
    headers.delete("a").must_be_same_as headers
    headers.to_a.must_equal [["b", "2"]]
  end

  it "does not alias the internal storage" do
    fields = [["a", "1"], ["b", "2"], ["a", "3"]]
    headers = Nack::Headers.new(fields).add("c", "4")
    fields[0][1] = "5"
    result = headers.to_a
    result << ["c", "5"]
    -> { result[0][1] = "5" }.must_raise FrozenError
    -> { result[3][1] = "5" }.must_raise FrozenError
    headers.to_a.must_equal [["a", "1"], ["b", "2"], ["a", "3"], ["c", "4"]]
  end
end
