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

  it "maps an immediate response" do
    response = [200, [], nil]
    Nack::Utils.map_response(response) { [it] }.must_equal [response]
  end

  it "maps a deferred response when its responder is called" do
    response = [200, [], nil]
    mapped_responder = nil
    deferred = Nack::Utils.map_response(->(responder) { mapped_responder = responder }) { [it] }
    responded = nil
    deferred.call(->(argument) { responded = argument })
    mapped_responder.call(response)
    responded.must_equal [response]
  end

  it "passes an exception to the responder without mapping it" do
    exception = RuntimeError.new
    deferred = Nack::Utils.map_response(->(responder) { responder.call(exception) }) { [it] }
    responded = nil
    deferred.call(->(argument) { responded = argument })
    responded.must_be_same_as exception
  end

  it "passes a StandardError the block raises to the responder" do
    exception = RuntimeError.new
    deferred = Nack::Utils.map_response(->(responder) { responder.call([200, [], nil]) }) { raise exception }
    responded = nil
    deferred.call(->(argument) { responded = argument })
    responded.must_be_same_as exception
  end

  it "lets any other exception the block raises reach the caller of the responder" do
    deferred = Nack::Utils.map_response(->(responder) { responder.call([200, [], nil]) }) { raise Exception } # standard:disable Lint/RaiseException
    -> { deferred.call(->(_) {}) }.must_raise Exception
  end

  it "raises SpecError on a second call of the responder, without mapping again" do
    calls = 0
    deferred = Nack::Utils.map_response(->(responder) { 2.times { responder.call([200, [], nil]) } }) { calls += 1 }
    -> { deferred.call(->(_) {}) }.must_raise Nack::SpecError
    calls.must_equal 1
  end

  it "forwards #cancel only to a deferred response that responds to it" do
    cancelable = Struct.new(:canceled) do
      def cancel
        self.canceled = true
      end
    end.new
    Nack::Utils.map_response(cancelable) {}.cancel
    cancelable.canceled.must_equal true
    Nack::Utils.map_response(->(_) {}) {}.wont_respond_to :cancel
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
end
