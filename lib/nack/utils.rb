# frozen_string_literal: true

require "cgi/escape"
require "uri"

module Nack
  module Utils
    module_function

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

    def get_header(pairs, name)
      pairs.assoc(name)&.last
    end

    def set_header(pairs, name, value)
      pairs.reject! { |key, _| key == name }
      pairs << [name, value]
      pairs
    end

    def delete_header(pairs, name)
      pairs.reject! { |key, _| key == name }
      pairs
    end

    def no_entity_body?(status, request)
      request.request_method.get_string == "HEAD" ||
        ((100..199).cover?(status) && status != 101) || status == 204 || status == 304
    end

    def body_size(body)
      case body
      when nil then 0
      when String then body.bytesize
      when IO::Buffer then body.size
      end
    end

    def body_to_string(body)
      case body
      when nil then "".b
      when String then body
      when IO::Buffer then body.get_string
      else
        string = "".b
        body.each { |chunk| string.append_as_bytes(chunk.is_a?(IO::Buffer) ? chunk.get_string : chunk.to_str) }
        string
      end
    ensure
      body.close if body.respond_to?(:close)
    end

    def valid_interim_status?(status)
      status.is_a?(Integer) && (100..199).cover?(status) && status != 101
    end

    def escape(string)
      URI.encode_www_form_component(string)
    end

    def unescape(string, encoding = Encoding::UTF_8)
      URI.decode_www_form_component(string, encoding)
    end

    def escape_html(string)
      CGI.escapeHTML(string)
    end

    def load_class(name, prefix)
      if name.start_with?("::")
        Object.const_get(name.delete_prefix("::"))
      else
        prefix.const_get(name, false)
      end
    end
  end
end
