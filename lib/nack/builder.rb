# frozen_string_literal: true

module Nack
  class Builder
    class DSL
      def initialize(&block)
        @middlewares = []
        @app = nil
        @mapping = []
        instance_exec(&block)
      end

      def use(middleware, ...)
        @middlewares << middleware.new(...)
        nil
      end

      def run(app)
        raise Error, "run given more than once" if @app
        @app = app.respond_to?(:to_app) ? app.to_app : app
        nil
      end

      def map(reference, &block)
        @mapping << [reference, DSL.new(&block).to_app]
        nil
      end

      def to_app
        app = @app
        app = URLMap.new(app ? [["/", app], *@mapping] : @mapping) unless @mapping.empty?
        raise Error, "missing run or map" unless app
        @middlewares.reverse_each { app = it.wrap(app).to_app }
        app
      end
    end
    private_constant :DSL

    def self.app(&block)
      new(&block).to_app
    end

    def initialize(&block)
      @block = Ractor.shareable_proc(&block)
      freeze
    end

    def to_app
      DSL.new(&@block).to_app
    end
  end
end
