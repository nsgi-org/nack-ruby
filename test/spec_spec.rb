# frozen_string_literal: true

require_relative "helper"

describe Nack::Spec do
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

  it "accepts final statuses in 200..599 or 101" do
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
    Nack::Spec.valid_content_length?(0).must_equal false
  end

  it "knows which responses carry no entity body" do
    request = Struct.new(:request_method)
    get = request.new(IO::Buffer.for("GET"))
    head = request.new(IO::Buffer.for("HEAD"))
    Nack::Spec.no_entity_body?(100, get).must_equal true
    Nack::Spec.no_entity_body?(199, get).must_equal true
    Nack::Spec.no_entity_body?(204, get).must_equal true
    Nack::Spec.no_entity_body?(304, get).must_equal true
    Nack::Spec.no_entity_body?(101, get).must_equal false
    Nack::Spec.no_entity_body?(200, get).must_equal false
    Nack::Spec.no_entity_body?(200, head).must_equal true
  end

  it "accepts interim statuses in 100..199 other than 101" do
    Nack::Spec.valid_interim_status?(100).must_equal true
    Nack::Spec.valid_interim_status?(199).must_equal true
    Nack::Spec.valid_interim_status?(99).must_equal false
    Nack::Spec.valid_interim_status?(101).must_equal false
    Nack::Spec.valid_interim_status?(200).must_equal false
    Nack::Spec.valid_interim_status?("100").must_equal false
  end
end
