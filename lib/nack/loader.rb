# frozen_string_literal: true

module Nack
  module Loader
    module_function

    def load(path)
      app = RubyVM::InstructionSequence.compile_file(path).eval
      raise Error, "responds to neither call nor to_app: #{path.inspect}" unless app.respond_to?(:call) || app.respond_to?(:to_app)
      app
    end
  end
end
