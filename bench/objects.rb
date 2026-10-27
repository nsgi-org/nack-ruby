# frozen_string_literal: true

module Bench
  class Middleware
    def initialize(app)
      @app = app
    end

    def call
      @app.call
    end
  end

  class Endpoint
    def call
    end
  end

  TEXT = "a"

  def self.chain(length)
    length.times.inject(Endpoint.new) { |app| Middleware.new(app) }
  end

  def self.keys(size)
    Array.new(size, &:to_s)
  end

  def self.table(size)
    keys(size).to_set
  end

  def self.regexp
    Regexp.new(TEXT)
  end
end
