# frozen_string_literal: true

module Nack
  class Middleware < Component
    def call(request)
      @app.call(request)
    end

    def wrap(app)
      middleware = clone(freeze: false)
      middleware.app = app
      middleware
    end

    protected

    attr_writer :app
  end
end
