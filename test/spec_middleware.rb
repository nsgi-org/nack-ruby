# frozen_string_literal: true

require_relative "helper"

describe Nack::Middleware do
  def map_response(response, &block)
    Class.new(Nack::Middleware) { public :map_response }.new.map_response(response, &block)
  end

  it "wraps an app in itself" do
    middleware = Nack::Middleware.new
    middleware.wrap(->(request) { "#{request}b" }).must_be_same_as middleware
    middleware.call("a").must_equal "ab"
  end

  it "raises Nack::Error on a second wrap" do
    middleware = Nack::Middleware.new.wrap(->(_) {})
    -> { middleware.wrap(->(_) {}) }.must_raise Nack::Error
  end

  it "maps an immediate response" do
    response = [200, [], nil]
    map_response(response) { [it] }.must_equal [response]
  end

  it "lets an exception the block raises for an immediate response reach the caller" do
    exception = RuntimeError.new
    (-> { map_response([]) { raise exception } }.must_raise RuntimeError).must_be_same_as exception
  end

  it "raises SpecError on a second call of the responder, without mapping again" do
    calls = 0
    deferred = map_response(->(responder) { 2.times { responder.call(nil) } }) { calls += 1 }
    -> { deferred.call(->(_) {}) }.must_raise Nack::SpecError
    calls.must_equal 1
  end

  it "maps anything but an exception passed to the responder" do
    deferred = map_response(->(responder) { responder.call(nil) }) { [it] }
    responded = nil
    deferred.call(->(argument) { responded = argument })
    responded.must_equal [nil]
  end

  it "passes a StandardError the block raises to the responder" do
    exception = RuntimeError.new
    deferred = map_response(->(responder) { responder.call(nil) }) { raise exception }
    responded = nil
    deferred.call(->(argument) { responded = argument })
    responded.must_be_same_as exception
  end

  it "lets any other exception the block raises reach the caller of the responder" do
    deferred = map_response(->(responder) { responder.call(nil) }) { raise Exception } # standard:disable Lint/RaiseException
    -> { deferred.call(->(_) {}) }.must_raise Exception
  end

  it "passes an exception to the responder without mapping it" do
    exception = Exception.new
    deferred = map_response(->(responder) { responder.call(exception) }) { [it] }
    responded = nil
    deferred.call(->(argument) { responded = argument })
    responded.must_be_same_as exception
  end

  it "forwards #cancel only to a deferred response that responds to it" do
    cancelable = Struct.new(:canceled) do
      def cancel
        self.canceled = true
      end
    end.new
    map_response(cancelable) {}.cancel
    cancelable.canceled.must_equal true
    map_response(->(_) {}) {}.wont_respond_to :cancel
  end
end
