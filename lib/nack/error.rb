# frozen_string_literal: true

module Nack
  class Error < StandardError; end

  class SpecError < Error; end

  class ParamError < Error; end
end
