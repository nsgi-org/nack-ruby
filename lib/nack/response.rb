# frozen_string_literal: true

module Nack
  class Response
    COOKIE_NAME = /\A[0-9A-Za-z!#$%&'*+\-.^_`|~]+\z/
    COOKIE_VALUE = /\A("?)[!#-+\--:<-\[\]-~]*\1\z/
    IMF_FIXDATE = "%a, %d %b %Y %H:%M:%S GMT"
    COOKIE_DOMAIN_LABEL = /[0-9A-Za-z](?:[0-9A-Za-z-]{0,61}[0-9A-Za-z])?/
    COOKIE_DOMAIN = /\A#{COOKIE_DOMAIN_LABEL}(?:\.#{COOKIE_DOMAIN_LABEL})*\z/
    COOKIE_PATH = /\A[ -:<-~]*\z/
    COOKIE_SAME_SITE = /\A(?:strict|lax|none)\z/i

    class BodyWithTrailers
      attr_reader :trailers

      def initialize(body, trailers)
        @body = body
        @trailers = trailers
      end

      def each
        yield @body
      end
    end
    private_constant :BodyWithTrailers

    attr_accessor :status
    attr_reader :headers, :body

    def initialize(status = 200, headers = [].freeze, body = nil)
      @status = status
      @headers = Headers.new(headers)
      @body = body ? body.b : "".b
    end

    def content_type
      headers["content-type"]
    end

    def content_type=(content_type)
      content_type ? headers["content-type"] = content_type : headers.delete("content-type")
    end

    def content_length
      content_length = headers["content-length"]
      content_length.to_i if Spec.valid_content_length?(content_length)
    end

    def content_length=(content_length)
      if content_length.nil?
        headers.delete("content-length")
      elsif content_length.is_a?(Integer) && content_length >= 0
        headers["content-length"] = content_length.to_s
      else
        raise SpecError, "invalid content length: #{content_length.inspect}"
      end
    end

    def location
      headers["location"]
    end

    def location=(location)
      location ? headers["location"] = location : headers.delete("location")
    end

    def redirect(location, status = 302)
      self.location = location
      self.status = status
    end

    def set_cookie(name, value, expires: nil, max_age: nil, domain: nil, path: nil, secure: false, http_only: false, same_site: nil)
      expires = expires&.getutc
      raise ArgumentError, "invalid cookie name: #{name.inspect}" unless COOKIE_NAME.match?(name)
      raise ArgumentError, "invalid cookie value: #{value.inspect}" unless COOKIE_VALUE.match?(value)
      raise ArgumentError, "invalid cookie expires: #{expires.inspect}" unless expires.nil? || (1900..9999).cover?(expires.year)
      raise ArgumentError, "invalid cookie max age: #{max_age.inspect}" if max_age && !(max_age.is_a?(Integer) && max_age.positive?)
      raise ArgumentError, "invalid cookie domain: #{domain.inspect}" unless domain.nil? || COOKIE_DOMAIN.match?(domain)
      raise ArgumentError, "invalid cookie path: #{path.inspect}" unless path.nil? || COOKIE_PATH.match?(path)
      raise ArgumentError, "invalid cookie same site: #{same_site.inspect}" unless same_site.nil? || COOKIE_SAME_SITE.match?(same_site)
      cookie = "#{name}=#{value}#{
        "; expires=#{expires.strftime(IMF_FIXDATE)}" if expires}#{
        "; max-age=#{max_age}" if max_age}#{
        "; domain=#{domain}" if domain}#{
        "; path=#{path}" if path}#{
        "; secure" if secure}#{
        "; httponly" if http_only}#{
        "; samesite=#{same_site}" if same_site}"
      # rfc6265bis section 4.1.1 forbids two set-cookie fields of one name in a response.
      headers.delete_if do |field_name, field_value|
        field_name == "set-cookie" && field_value.start_with?(name) && field_value.match?(/\G[ \t]*=/, name.size)
      end
      headers.add("set-cookie", cookie)
    end

    def delete_cookie(name, **attributes)
      set_cookie(name, "", **attributes, expires: Time.at(0), max_age: nil)
    end

    def write(chunk)
      @body.append_as_bytes(chunk)
    end

    def trailers
      @trailers ||= Headers.new
    end

    def finish
      return [status, headers.to_a, ""] if status == 204 || status == 205 || status == 304
      trailer_fields = @trailers&.to_a
      [status, headers.to_a, (trailer_fields.nil? || trailer_fields.empty?) ? body : BodyWithTrailers.new(body, trailer_fields)]
    end
  end
end
