# frozen_string_literal: true

module Nack
  class Component
    def to_app
      prepare_app
      self
    end

    private

    def prepare_app
    end
  end
end
