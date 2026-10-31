# frozen_string_literal: true

require "cgi/escape"

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
      string =
        case string.encoding
        when Encoding::BINARY then string
        when Encoding::UTF_8 then string.valid_encoding? ? string : string.scrub
        else string.ascii_only? ? string : string.encode(Encoding::UTF_8, invalid: :replace, undef: :replace)
        end
      escaped = CGI.escape(string)
      # CGI.escape leaves ~ and encodes *; the WHATWG set is the reverse.
      return escaped unless escaped.include?("%2A") || escaped.include?("~")
      escaped.gsub(/%2A|~/, "%2A" => "*", "~" => "%7E")
    end

    def unescape(string)
      CGI.unescape(string).force_encoding(Encoding::UTF_8).scrub!
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
