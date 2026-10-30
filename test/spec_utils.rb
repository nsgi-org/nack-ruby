# frozen_string_literal: true

require_relative "helper"

describe Nack::Utils do
  it "measures a body in bytes" do
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

  it "escapes a form component per WHATWG" do
    Nack::Utils.escape(" *~é").must_equal "+*%7E%C3%A9"
    Nack::Utils.escape("\xff").must_equal "%EF%BF%BD"
    Nack::Utils.escape("é".encode(Encoding::ISO_8859_1)).must_equal "%C3%A9"
  end

  it "escapes a binary string byte for byte" do
    Nack::Utils.escape("\xff".b).must_equal "%FF"
  end

  it "unescapes a form component per WHATWG" do
    Nack::Utils.unescape("+%c3%A9").must_equal " é"
    Nack::Utils.unescape("%ag").must_equal "%ag"
    Nack::Utils.unescape("%a").must_equal "%a"
    Nack::Utils.unescape("\xff".b).must_equal "\uFFFD"
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
