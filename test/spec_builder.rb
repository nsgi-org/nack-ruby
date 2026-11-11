# frozen_string_literal: true

require_relative "helper"

class Suffix < Nack::Middleware
  def initialize(*args, **kwargs, &block)
    @suffix = [*args, *kwargs.values, block&.call].join
  end

  def call(request) = "#{super}#{@suffix}"
end

describe Nack::Builder do
  def request(path:)
    Nack::Request.new(Struct.new(:path).new(IO::Buffer.for(path)))
  end

  it "uses middlewares outermost first, created with arguments and a block" do
    app = Nack::Builder.app do
      use(Suffix, "b", key: "c") { "d" }
      use Suffix, "e"
      run ->(request) { request }
    end
    app.call("a").must_equal "aebcd"
  end

  it "runs an app, building a component" do
    component = Class.new(Nack::Component) do
      def prepare_app = @prepared = true

      def call(_) = @prepared
    end
    Nack::Builder.app { run component.new }.call("a").must_equal true
  end

  it "raises Nack::Error on a second run" do
    -> { Nack::Builder.app { 2.times { run Object.new } } }.must_raise Nack::Error
  end

  it "maps references to their own stacks, mounting the app run outside at the root" do
    app = Nack::Builder.app do
      map("/a") { run ->(request) { request.path_info } }
      run ->(_) { "b" }
    end
    app.call(request(path: "/a/c")).must_equal "/c"
    app.call(request(path: "/c")).must_equal "b"
    Nack::Builder.app { map("/a") { run ->(_) { "a" } } }.call(request(path: "/b")).first.must_equal 404
    lambda do
      Nack::Builder.app do
        run ->(_) {}
        map("/a") { use Suffix }
      end
    end.must_raise Nack::Error
  end

  it "rejects a reference mapped twice or to the root alongside run" do
    -> { Nack::Builder.app { 2.times { map("/a") { run ->(_) {} } } } }.must_raise ArgumentError
    lambda do
      Nack::Builder.app do
        map("/") { run ->(_) {} }
        run ->(_) {}
      end
    end.must_raise ArgumentError
  end

  it "returns nil from use, run and map" do
    app = Nack::Builder.app do
      returns = [use(Suffix), map("/a") { run ->(_) {} }]
      returns << run(->(_) { returns })
    end
    app.call(request(path: "/")).must_equal "[nil, nil, nil]"
  end

  it "raises Nack::Error without run or map" do
    -> { Nack::Builder.app {} }.must_raise Nack::Error
  end

  it "builds a stack in another Ractor from a shareable blueprint" do
    builder = Nack::Builder.new do
      use Suffix, "b"
      run ->(request) { request }
    end
    Ractor.shareable?(builder).must_equal true
    Ractor.new(builder) { it.to_app.call("a") }.value.must_equal "ab"
  end

  it "raises Ractor::IsolationError when the block captures an unshareable object" do
    object = Object.new
    -> { Nack::Builder.new { object } }.must_raise Ractor::IsolationError
  end

  it "builds an independent stack on each call" do
    builder = Nack::Builder.new { run Object.new }
    builder.to_app.wont_be_same_as builder.to_app
  end
end
