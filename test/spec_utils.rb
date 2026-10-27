# frozen_string_literal: true

require_relative "helper"

describe Nack::Utils do
  it "accepts header names that are lowercase tokens" do
    Nack::Utils.valid_header_name?("09az!#$%&'*+-.^_`|~").must_equal true
    Nack::Utils.valid_header_name?("").must_equal false
    Nack::Utils.valid_header_name?("A").must_equal false
    Nack::Utils.valid_header_name?("a\na").must_equal false
    Nack::Utils.valid_header_name?("\xff").must_equal false
    Nack::Utils.valid_header_name?(:a).must_equal false
  end

  it "accepts header values that are message text" do
    Nack::Utils.valid_header_value?("").must_equal true
    Nack::Utils.valid_header_value?("a \tb").must_equal true
    Nack::Utils.valid_header_value?("\xff").must_equal true
    Nack::Utils.valid_header_value?("a\0a").must_equal false
    Nack::Utils.valid_header_value?("a\na").must_equal false
    Nack::Utils.valid_header_value?("a\ra").must_equal false
    Nack::Utils.valid_header_value?(" a").must_equal false
    Nack::Utils.valid_header_value?("\ta").must_equal false
    Nack::Utils.valid_header_value?("a ").must_equal false
    Nack::Utils.valid_header_value?("a\t").must_equal false
    Nack::Utils.valid_header_value?(:a).must_equal false
  end

  it "accepts final statuses in 200..599 or 101" do
    Nack::Utils.valid_status?(101).must_equal true
    Nack::Utils.valid_status?(200).must_equal true
    Nack::Utils.valid_status?(599).must_equal true
    Nack::Utils.valid_status?(199).must_equal false
    Nack::Utils.valid_status?(600).must_equal false
    Nack::Utils.valid_status?("200").must_equal false
  end

  it "knows which headers govern the connection" do
    %w[connection keep-alive proxy-connection te transfer-encoding].each do |name|
      Nack::Utils.connection_header?(name, 101).must_equal true
    end
    Nack::Utils.connection_header?("upgrade", 200).must_equal true
    Nack::Utils.connection_header?("upgrade", 101).must_equal false
    Nack::Utils.connection_header?("a", 200).must_equal false
  end

  it "accepts content-length values that are decimal numbers" do
    Nack::Utils.valid_content_length?("09").must_equal true
    Nack::Utils.valid_content_length?("").must_equal false
    Nack::Utils.valid_content_length?("0\n0").must_equal false
    Nack::Utils.valid_content_length?("\xff").must_equal false
    Nack::Utils.valid_content_length?(0).must_equal false
  end

  it "returns the first value for a header name" do
    pairs = [["a", "1"], ["b", "2"], ["b", "3"]]
    Nack::Utils.get_header(pairs, "b").must_equal "2"
    Nack::Utils.get_header(pairs, "c").must_be_nil
  end

  it "replaces all occurrences when setting a header" do
    pairs = [["a", "1"], ["b", "2"], ["a", "3"]]
    Nack::Utils.set_header(pairs, "a", "4")
    pairs.must_equal [["b", "2"], ["a", "4"]]
  end

  it "appends when setting a header not yet present" do
    pairs = [["a", "1"]]
    Nack::Utils.set_header(pairs, "b", "2")
    pairs.must_equal [["a", "1"], ["b", "2"]]
  end

  it "removes all occurrences when deleting a header" do
    pairs = [["a", "1"], ["b", "2"], ["a", "3"]]
    Nack::Utils.delete_header(pairs, "a")
    pairs.must_equal [["b", "2"]]
  end

  it "knows which responses carry no entity body" do
    request = Struct.new(:request_method)
    get = request.new(IO::Buffer.for("GET"))
    head = request.new(IO::Buffer.for("HEAD"))
    Nack::Utils.no_entity_body?(100, get).must_equal true
    Nack::Utils.no_entity_body?(199, get).must_equal true
    Nack::Utils.no_entity_body?(204, get).must_equal true
    Nack::Utils.no_entity_body?(304, get).must_equal true
    Nack::Utils.no_entity_body?(101, get).must_equal false
    Nack::Utils.no_entity_body?(200, get).must_equal false
    Nack::Utils.no_entity_body?(200, head).must_equal true
  end

  it "measures body size in bytes" do
    Nack::Utils.body_size(nil).must_equal 0
    Nack::Utils.body_size("é").must_equal 2
    Nack::Utils.body_size(IO::Buffer.for("é")).must_equal 2
    Nack::Utils.body_size(["a"]).must_be_nil
  end

  it "reads a body into a string" do
    Nack::Utils.body_to_string(nil).must_equal ""
    body = "a"
    Nack::Utils.body_to_string(body).must_be_same_as body
    Nack::Utils.body_to_string(IO::Buffer.for("a")).must_equal "a"
    Nack::Utils.body_to_string(["é", IO::Buffer.for("\xff")]).must_equal "é\xff".b
  end

  it "closes a body whether or not reading it fails" do
    body_class = Struct.new(:error, :closed) do
      def each
        raise error if error
      end

      def close
        self.closed = true
      end
    end
    succeeded = body_class.new
    Nack::Utils.body_to_string(succeeded)
    succeeded.closed.must_equal true
    failed = body_class.new(RuntimeError)
    -> { Nack::Utils.body_to_string(failed) }.must_raise RuntimeError
    failed.closed.must_equal true
  end

  it "accepts interim statuses in 100..199 other than 101" do
    Nack::Utils.valid_interim_status?(100).must_equal true
    Nack::Utils.valid_interim_status?(199).must_equal true
    Nack::Utils.valid_interim_status?(99).must_equal false
    Nack::Utils.valid_interim_status?(101).must_equal false
    Nack::Utils.valid_interim_status?(200).must_equal false
    Nack::Utils.valid_interim_status?("100").must_equal false
  end

  it "escapes and unescapes form components" do
    Nack::Utils.escape(" &é").must_equal "+%26%C3%A9"
    Nack::Utils.unescape("+%26%C3%A9").must_equal " &é"
    Nack::Utils.unescape("%E9", Encoding::ISO_8859_1).must_equal "é".encode(Encoding::ISO_8859_1)
  end

  it "escapes HTML" do
    Nack::Utils.escape_html(%(&<>"')).must_equal "&amp;&lt;&gt;&quot;&#39;"
  end

  it "resolves a class name against a prefix" do
    Nack::Utils.load_class("Error", Nack).must_equal Nack::Error
    Nack::Utils.load_class("::String", Nack).must_equal String
    -> { Nack::Utils.load_class("String", Nack) }.must_raise NameError
  end
end
