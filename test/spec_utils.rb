# frozen_string_literal: true

require_relative "helper"

describe Nack::Utils do
  it "returns the first value for a header name" do
    pairs = [["a", "1"], ["b", "2"], ["b", "3"]]
    Nack::Utils.get_header(pairs, "b").must_equal "2"
    Nack::Utils.get_header(pairs, "c").must_be_nil
  end

  it "replaces all occurrences when setting a header" do
    pairs = [["a", "1"], ["b", "2"], ["a", "3"]]
    Nack::Utils.set_header(pairs, "a", "4")
    pairs.must_equal [["a", "4"], ["b", "2"]]
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

  it "measures body size in bytes" do
    Nack::Utils.body_bytesize(nil).must_equal 0
    Nack::Utils.body_bytesize("é").must_equal 2
    Nack::Utils.body_bytesize(IO::Buffer.for("é")).must_equal 2
    Nack::Utils.body_bytesize(["a"]).must_be_nil
  end

  it "reads a body into a string" do
    Nack::Utils.read_body(nil).must_equal ""
    body = "a"
    Nack::Utils.read_body(body).must_be_same_as body
    Nack::Utils.read_body(IO::Buffer.for("a")).must_equal "a"
    Nack::Utils.read_body(["é", IO::Buffer.for("\xff")]).must_equal "é\xff".b
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
    Nack::Utils.read_body(succeeded)
    succeeded.closed.must_equal true
    failed = body_class.new(RuntimeError)
    -> { Nack::Utils.read_body(failed) }.must_raise RuntimeError
    failed.closed.must_equal true
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
