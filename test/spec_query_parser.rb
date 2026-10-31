# frozen_string_literal: true

require_relative "helper"

describe Nack::QueryParser do
  let(:parser) { Nack::QueryParser.new }

  it "is shareable across Ractors" do
    Ractor.shareable?(parser).must_equal true
  end

  it "parses a query per WHATWG" do
    parser.parse_query("a=1&b=2&a=3").must_equal [["a", "1"], ["b", "2"], ["a", "3"]]
    parser.parse_query("&").must_equal []
    parser.parse_query("a;b").must_equal [["a;b", ""]]
    parser.parse_query("a==").must_equal [["a", "="]]
    parser.parse_query("a").must_equal [["a", ""]]
    parser.parse_query("+=+").must_equal [[" ", " "]]
    parser.parse_query("\xff").must_equal [["\uFFFD", ""]]
  end

  it "raises ParamError beyond the parameter limit" do
    limited = Nack::QueryParser.new(param_limit: 1)
    limited.parse_query("a").must_equal [["a", ""]]
    -> { limited.parse_query("a&b") }.must_raise Nack::ParamError
  end

  it "parses a nested query" do
    parser.parse_nested_query("a=1&a=2").must_equal({"a" => "2"})
    parser.parse_nested_query("a[]=1&a[]=2").must_equal({"a" => ["1", "2"]})
    parser.parse_nested_query("a[b]=1").must_equal({"a" => {"b" => "1"}})
    parser.parse_nested_query("a[b][]=1").must_equal({"a" => {"b" => ["1"]}})
  end

  it "keeps a malformed nested name flat" do
    parser.parse_nested_query("[]&]a[]&a[[]&a[]]").must_equal({"[]" => "", "]a[]" => "", "a[[]" => "", "a[]]" => ""})
  end

  it "raises ParamError beyond the depth limit" do
    limited = Nack::QueryParser.new(depth_limit: 1)
    limited.parse_nested_query("a").must_equal({"a" => ""})
    -> { limited.parse_nested_query("a[b]") }.must_raise Nack::ParamError
  end

  it "reuses the last array element unless occupied" do
    parser.parse_nested_query("a[][]=1&a[][]=2").must_equal({"a" => [["1", "2"]]})
    parser.parse_nested_query("a[][b][c]=1&a[][b][d]=2&a[][b][c]=3").must_equal({"a" => [{"b" => {"c" => "1", "d" => "2"}}, {"b" => {"c" => "3"}}]})
    parser.parse_nested_query("a[][b]=1&a[][b][c]=2").must_equal({"a" => [{"b" => "1"}, {"b" => {"c" => "2"}}]})
    parser.parse_nested_query("a[][]=1&a[][b]=2").must_equal({"a" => [["1"], {"b" => "2"}]})
  end

  it "raises ParamError on conflicting shapes" do
    ["a[]&a", "a[b]&a", "a&a[]", "a&a[b]", "a[]&a[b]", "a[b]&a[]"].each do |query|
      -> { parser.parse_nested_query(query) }.must_raise Nack::ParamError
    end
  end

  it "builds a query per WHATWG" do
    parser.build_query([["a", "1"], ["b", "2"], ["a", "3"]]).must_equal "a=1&b=2&a=3"
    parser.build_query([["a", ""]]).must_equal "a="
    parser.build_query([[" ", " "]]).must_equal "+=+"
  end

  it "builds a nested query" do
    params = {"a" => ["1", "2"], "b" => {"c" => "3"}, "d" => [{"e" => "4", "f" => "5"}, {"e" => "6"}]}
    query = parser.build_nested_query(params)
    query.must_equal "a%5B%5D=1&a%5B%5D=2&b%5Bc%5D=3&d%5B%5D%5Be%5D=4&d%5B%5D%5Bf%5D=5&d%5B%5D%5Be%5D=6"
    parser.parse_nested_query(query).must_equal params
    parser.build_nested_query({" " => {" " => " "}}).must_equal "+%5B+%5D=+"
    parser.build_nested_query({"a" => [], "b" => {}}).must_equal ""
  end
end
