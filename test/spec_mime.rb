# frozen_string_literal: true

require_relative "helper"

describe Nack::MIME do
  it "is shareable across Ractors" do
    Ractor.shareable?(Nack::MIME::TYPES).must_equal true
  end

  it "returns the media type of an extension with or without a dot, in any case" do
    Nack::MIME[".html"].must_equal "text/html"
    Nack::MIME["html"].must_equal "text/html"
    Nack::MIME[".HTML"].must_equal "text/html"
    Nack::MIME["HTML"].must_equal "text/html"
  end

  it "returns nil for an unknown extension" do
    Nack::MIME[".unknown"].must_be_nil
    Nack::MIME[""].must_be_nil
  end
end
