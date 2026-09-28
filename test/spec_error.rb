# frozen_string_literal: true

require_relative "helper"

describe Nack::Error do
  it "descends from StandardError" do
    Nack::Error.superclass.must_equal StandardError
  end

  it "is the base of SpecError and ParamError" do
    Nack::SpecError.superclass.must_equal Nack::Error
    Nack::ParamError.superclass.must_equal Nack::Error
  end
end
