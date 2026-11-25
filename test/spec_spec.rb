# frozen_string_literal: true

require_relative "helper"

describe Nack::Spec do
  it "accepts schemes that are lowercase" do
    Nack::Spec.valid_scheme?("az09+-.").must_equal true
    Nack::Spec.valid_scheme?("").must_equal false
    Nack::Spec.valid_scheme?("0").must_equal false
    Nack::Spec.valid_scheme?("A").must_equal false
    Nack::Spec.valid_scheme?("aA").must_equal false
  end

  it "accepts methods that are tokens" do
    Nack::Spec.valid_method?("09AZaz!#$%&'*+-.^_`|~").must_equal true
    Nack::Spec.valid_method?("").must_equal false
    Nack::Spec.valid_method?("a a").must_equal false
  end

  it "accepts authorities that are a host with an optional port" do
    Nack::Spec.valid_authority?("[::]").must_equal true
    Nack::Spec.valid_authority?("[v09AFaf.09AZaz_-.~!$&'()*+,;=:]").must_equal true
    Nack::Spec.valid_authority?("09AZaz_-.~!$&'()*+,;=%41:09").must_equal true
    Nack::Spec.valid_authority?("a:").must_equal true
    Nack::Spec.valid_authority?("").must_equal false
    Nack::Spec.valid_authority?("u@a").must_equal false
    Nack::Spec.valid_authority?("%4").must_equal false
    Nack::Spec.valid_authority?("a:b").must_equal false
    Nack::Spec.valid_authority?("[1.2.3.4]").must_equal false
    Nack::Spec.valid_authority?("[:::]").must_equal false
    Nack::Spec.valid_authority?("[::%1]").must_equal false
  end

  it "accepts header names that are lowercase tokens" do
    Nack::Spec.valid_header_name?("09az!#$%&'*+-.^_`|~").must_equal true
    Nack::Spec.valid_header_name?("").must_equal false
    Nack::Spec.valid_header_name?("A").must_equal false
    Nack::Spec.valid_header_name?("a\na").must_equal false
    Nack::Spec.valid_header_name?("\xff").must_equal false
    Nack::Spec.valid_header_name?(:a).must_equal false
  end

  it "accepts header values that are message text" do
    Nack::Spec.valid_header_value?("").must_equal true
    Nack::Spec.valid_header_value?("a \tb").must_equal true
    Nack::Spec.valid_header_value?("\xff").must_equal true
    Nack::Spec.valid_header_value?("a\0a").must_equal false
    Nack::Spec.valid_header_value?("a\na").must_equal false
    Nack::Spec.valid_header_value?("a\ra").must_equal false
    Nack::Spec.valid_header_value?(" a").must_equal false
    Nack::Spec.valid_header_value?("\ta").must_equal false
    Nack::Spec.valid_header_value?("a ").must_equal false
    Nack::Spec.valid_header_value?("a\t").must_equal false
    Nack::Spec.valid_header_value?(:a).must_equal false
  end

  it "accepts fields that are a pair of a header name and value" do
    Nack::Spec.valid_field?(["a", "1"]).must_equal true
    Nack::Spec.valid_field?(["a", "1", "2"]).must_equal false
    Nack::Spec.valid_field?(["A", "1"]).must_equal false
    Nack::Spec.valid_field?(["a", " "]).must_equal false
    Nack::Spec.valid_field?("a1").must_equal false
  end

  it "accepts final statuses" do
    Nack::Spec.valid_status?(101).must_equal true
    Nack::Spec.valid_status?(200).must_equal true
    Nack::Spec.valid_status?(599).must_equal true
    Nack::Spec.valid_status?(199).must_equal false
    Nack::Spec.valid_status?(600).must_equal false
    Nack::Spec.valid_status?("200").must_equal false
  end

  it "knows which headers govern the connection" do
    %w[connection keep-alive proxy-connection te transfer-encoding].each do |name|
      Nack::Spec.connection_header?(name, 101).must_equal true
    end
    Nack::Spec.connection_header?("upgrade", 200).must_equal true
    Nack::Spec.connection_header?("upgrade", 101).must_equal false
    Nack::Spec.connection_header?("a", 200).must_equal false
  end

  it "accepts content-length values that are decimal numbers" do
    Nack::Spec.valid_content_length?("09").must_equal true
    Nack::Spec.valid_content_length?("").must_equal false
    Nack::Spec.valid_content_length?("0\n0").must_equal false
    Nack::Spec.valid_content_length?("\xff").must_equal false
    Nack::Spec.valid_content_length?(:a).must_equal false
  end

  it "knows which responses carry no content" do
    Nack::Spec.no_content?(200, "HEAD").must_equal true
    Nack::Spec.no_content?(204, "GET").must_equal true
    Nack::Spec.no_content?(205, "GET").must_equal true
    Nack::Spec.no_content?(304, "GET").must_equal true
    Nack::Spec.no_content?(200, "GET").must_equal false
  end

  it "accepts interim statuses" do
    Nack::Spec.valid_interim_status?(100).must_equal true
    Nack::Spec.valid_interim_status?(199).must_equal true
    Nack::Spec.valid_interim_status?(99).must_equal false
    Nack::Spec.valid_interim_status?(101).must_equal false
    Nack::Spec.valid_interim_status?(200).must_equal false
    Nack::Spec.valid_interim_status?("100").must_equal false
  end

  it "knows which responses switch to a tunnel" do
    Nack::Spec.switches_to_tunnel?(299, [], "CONNECT", "HTTP/1.1", []).must_equal true
    Nack::Spec.switches_to_tunnel?(299, [], "GET", "HTTP/1.1", []).must_equal false
    Nack::Spec.switches_to_tunnel?(300, [], "CONNECT", "HTTP/1.1", []).must_equal false
    upgrade = [["upgrade", "a"], ["upgrade", "b, c"]]
    Nack::Spec.switches_to_tunnel?(101, [["upgrade", "C"]], "GET", "HTTP/1.1", upgrade).must_equal true
    Nack::Spec.switches_to_tunnel?(101, [["upgrade", "a"]], "GET", "HTTP/2", upgrade).must_equal false
    Nack::Spec.switches_to_tunnel?(101, [], "GET", "HTTP/1.1", upgrade).must_equal false
    Nack::Spec.switches_to_tunnel?(101, [["upgrade", "a, d"]], "GET", "HTTP/1.1", upgrade).must_equal false
  end
end
