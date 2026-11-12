# frozen_string_literal: true

require_relative "helper"
require "tempfile"

describe Nack::Loader do
  def with_file(source)
    Tempfile.create do |file|
      file.write(source)
      file.close
      yield file.path
    end
  end

  it "honors magic comments" do
    with_file("# frozen_string_literal: true\n->(_) { \"a\" }") do |path|
      Nack::Loader.load(path).call(nil).frozen?.must_equal true
    end
  end

  it "takes the last expression, evaluated at a top level of its own" do
    with_file("a = 1\nproc { [self, Module.nesting, local_variables] }") do |path|
      Nack::Loader.load(path).call(nil).must_equal [TOPLEVEL_BINDING.receiver, [], [:a]]
      TOPLEVEL_BINDING.local_variable_defined?(:a).must_equal false
    end
  end

  it "returns a result responding to to_app without building it" do
    with_file("Class.new(Nack::Component) { def prepare_app = raise }.new") do |path|
      Nack::Loader.load(path).must_be_kind_of Nack::Component
    end
  end

  it "raises Nack::Error when the result responds to neither call nor to_app" do
    with_file("Object.new") do |path|
      -> { Nack::Loader.load(path) }.must_raise Nack::Error
    end
  end

  it "reports the file path in backtraces" do
    with_file("raise") do |path|
      -> { Nack::Loader.load(path) }.must_raise(RuntimeError).backtrace_locations.first.path.must_equal path
    end
  end
end
