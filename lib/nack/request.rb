# frozen_string_literal: true

module Nack
  class Request
    AUTHORITY = /\A(\[[^\[\]]*\]|[^\[\]:]+)(?::([0-9]+)|:)?\z/
    DEFAULT_PORTS = Ractor.make_shareable({"http" => 80, "https" => 443})
    QUERY_PARSER = QueryParser.new

    attr_writer :request_method, :script_name, :path_info, :query_string, :headers, :body

    def initialize(source)
      @source = source
    end

    def scheme
      @source.scheme
    end

    def ssl?
      scheme == "https"
    end

    def remote_address
      @source.remote_address
    end

    def connection
      @source.connection
    end

    def request_method
      @request_method ||= @source.request_method.get_string.freeze
    end

    def protocol
      @source.protocol
    end

    def authority
      @source.authority
    end

    def host
      host_and_port.first
    end

    def port
      host_and_port.last
    end

    def script_name
      @script_name ||= ""
    end

    def path_info
      @path_info ||= @source.path&.get_string.freeze || ""
    end

    def query_string
      @query_string ||= @source.query&.get_string.freeze || ""
    end

    def GET
      query_string = self.query_string
      return @query_params if @parsed_query_string.equal?(query_string)
      @parsed_query_string = query_string
      @query_params = QUERY_PARSER.parse_nested_query(query_string)
    end

    def headers
      @headers ||= Headers.new(@source.headers.map { |name, value| [name.get_string.freeze, value.get_string.freeze].freeze })
    end

    def content_type
      headers["content-type"]
    end

    def media_type
      content_type = self.content_type
      return unless content_type
      content_type.byteslice(0, content_type.index(";") || content_type.bytesize).rstrip.downcase
    end

    def cookies
      cookie = headers["cookie"]
      return @cookies if @cookies && @parsed_cookie.equal?(cookie)
      @parsed_cookie = cookie
      @cookies = {}
      cookie&.split(";") do |pair|
        pair.strip!
        next if pair.empty?
        separator = pair.index("=")
        name = separator ? pair.byteslice(0, separator) : ""
        @cookies[name] ||= separator ? pair.byteslice(separator + 1, pair.bytesize) : pair
      end
      @cookies
    end

    def content_length
      @source.content_length
    end

    def variable(name)
      @source.variable(name)
    end

    def body
      @body ||= @source.body
    end

    def POST
      body = self.body
      return @form_params if @parsed_body.equal?(body)
      @parsed_body = body
      @form_params = (media_type == "application/x-www-form-urlencoded") ? QUERY_PARSER.parse_nested_query(read_body) : {}
    end

    def params
      self.GET.merge(self.POST)
    end

    def trailers
      @source.trailers
    end

    def inform(status, headers)
      @source.inform(status, headers)
    end

    def tunnel
      @source.tunnel
    end

    def context
      @context ||= {}
    end

    private

    def host_and_port
      @host_and_port ||=
        if (match = AUTHORITY.match(@source.authority&.get_string)).nil? then [nil, nil]
        elsif match[2].nil? then [match[1], DEFAULT_PORTS[scheme]]
        elsif (port = match[2].to_i) <= 65_535 then [match[1], port]
        else [nil, nil]
        end
    end

    def read_body
      string = "".b
      while (chunk = body.read)
        string.append_as_bytes(chunk.get_string)
      end
      string
    end
  end
end
