# frozen_string_literal: true

require "cgi/escape"
require "uri"

module Nack
  module Utils
    module_function

    def body_bytesize(body)
      case body
      when nil then 0
      when String then body.bytesize
      when IO::Buffer then body.size
      end
    end

    def read_body(body)
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
