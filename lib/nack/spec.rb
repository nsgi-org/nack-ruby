# frozen_string_literal: true

require "ipaddr"

module Nack
  module Spec
    AUTHORITY = /\A(?:\[(?:(?<ipv6>[\h:.]+)|v\h+\.[\w\-.~!$&'()*+,;=:]+)\]|(?:[\w\-.~!$&'()*+,;=]|%\h\h)+)(?::\d*)?\z/

    module_function

    def valid_scheme?(scheme)
      /\A[a-z][0-9a-z+\-.]*\z/.match?(scheme)
    end

    def valid_method?(method)
      /\A[0-9A-Za-z!#$%&'*+\-.^_`|~]+\z/.match?(method)
    end

    def valid_authority?(authority)
      match = AUTHORITY.match(authority) or return false
      match[:ipv6].nil? || IPAddr.new(match[:ipv6]).ipv6?
    rescue IPAddr::InvalidAddressError
      false
    end

    def valid_header_name?(name)
      name.is_a?(String) && name.ascii_only? && /\A[0-9a-z!#$%&'*+\-.^_`|~]+\z/.match?(name)
    end

    def valid_header_value?(value)
      value.is_a?(String) && !value.start_with?(" ", "\t") && !value.end_with?(" ", "\t") &&
        !value.include?("\0") && !value.include?("\n") && !value.include?("\r")
    end

    def valid_status?(status)
      status.is_a?(Integer) && ((200..599).cover?(status) || status == 101)
    end

    def connection_header?(name, status)
      case name
      when "connection", "keep-alive", "proxy-connection", "te", "transfer-encoding" then true
      when "upgrade" then status != 101
      else false
      end
    end

    def valid_content_length?(value)
      value.is_a?(String) && value.ascii_only? && /\A[0-9]+\z/.match?(value)
    end

    def no_content?(status, method)
      method == "HEAD" || status == 204 || status == 205 || status == 304
    end

    def valid_interim_status?(status)
      status.is_a?(Integer) && (100..199).cover?(status) && status != 101
    end
  end
end
