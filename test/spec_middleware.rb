# frozen_string_literal: true

require_relative "helper"

describe Nack::Middleware do
  it "wraps an app in a copy of a frozen instance" do
    Nack::Middleware.new.freeze.wrap(->(request) { "#{request}b" }).call("a").must_equal "ab"
  end

  it "wraps an app in a copy keeping its singleton methods" do
    middleware = Nack::Middleware.new
    def middleware.call(request) = "#{super}c"
    middleware.wrap(->(request) { "#{request}b" }).call("a").must_equal "abc"
  end
end
