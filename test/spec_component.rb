# frozen_string_literal: true

require_relative "helper"

describe Nack::Component do
  it "returns itself as the app" do
    component = Nack::Component.new
    component.to_app.must_be_same_as component
  end

  it "prepares itself as the app" do
    component = Class.new(Nack::Component) do
      attr_reader :prepared

      def prepare_app
        @prepared = true
      end
    end.new
    component.to_app.prepared.must_equal true
  end
end
