# frozen_string_literal: true

module Nack
  class Middleware < Component
    class MappedResponder
      def initialize(responder, block)
        @responder = responder
        @block = block
        @called = false
      end

      def call(response)
        raise SpecError, "responder called more than once" if @called
        @called = true
        unless response.is_a?(Exception)
          response = begin
            @block.call(response)
          rescue => exception
            exception
          end
        end
        @responder.call(response)
      end
    end
    private_constant :MappedResponder

    class MappedDeferredResponse
      def initialize(deferred_response, block)
        @deferred_response = deferred_response
        @block = block
      end

      def call(responder)
        @deferred_response.call(MappedResponder.new(responder, @block))
      end
    end
    private_constant :MappedDeferredResponse

    class CancelableMappedDeferredResponse < MappedDeferredResponse
      def cancel
        @deferred_response.cancel
      end
    end
    private_constant :CancelableMappedDeferredResponse

    def call(request)
      @app.call(request)
    end

    def wrap(app)
      raise Error, "wrap called more than once" if @app
      @app = app
      self
    end

    private

    def map_response(response, &block)
      return yield(response) if response.is_a?(Array)
      (response.respond_to?(:cancel) ? CancelableMappedDeferredResponse : MappedDeferredResponse).new(response, block)
    end
  end
end
