# frozen_string_literal: true

require_relative "lib/nack/version"

Gem::Specification.new do |spec|
  spec.name = "nack"
  spec.version = Nack::VERSION
  spec.summary = "Ruby toolkit for NSGI applications"
  spec.description = <<~DESCRIPTION
    Middleware with a composition DSL, request/response conveniences,
    path-based dispatch, and a host-free test kit for applications
    targeting the NSGI Ruby application contract.
  DESCRIPTION
  spec.authors = ["himura467"]
  spec.homepage = "https://github.com/nsgi-org/nack-ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"

  spec.metadata = {
    "source_code_uri" => "https://github.com/nsgi-org/nack-ruby",
    "bug_tracker_uri" => "https://github.com/nsgi-org/nack-ruby/issues",
    "rubygems_mfa_required" => "true"
  }

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "minitest"
end
