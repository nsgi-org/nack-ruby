# frozen_string_literal: true

require_relative "helper"

describe Nack::Middleware do
  it "wraps an app in itself" do
    middleware = Nack::Middleware.new
    middleware.wrap(->(request) { "#{request}b" }).must_be_same_as middleware
    middleware.call("a").must_equal "ab"
  end

  it "raises Nack::Error on a second wrap" do
    middleware = Nack::Middleware.new.wrap(->(_) {})
    -> { middleware.wrap(->(_) {}) }.must_raise Nack::Error
  end
end
