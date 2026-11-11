# frozen_string_literal: true

module Nack
  class Middleware < Component
    def call(request)
      @app.call(request)
    end

    def wrap(app)
      raise Error, "wrap called more than once" if @app
      @app = app
      self
    end
  end
end
