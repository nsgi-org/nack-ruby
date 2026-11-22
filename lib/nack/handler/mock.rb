# frozen_string_literal: true

require_relative "../../nack"

module Nack
  module Handler
    class Mock
      class Error < StandardError
        attr_reader :condition

        def initialize(condition)
          super
          @condition = condition
        end
      end

      Response = Data.define(:status, :headers, :body, :trailers, :interim_responses)

      class Exchange
        def initialize(method, http_version, headers)
          @method = method
          @http_version = http_version
          @headers = headers
          @buffers = []
          @call_fiber = nil
          @returned = false
          @handed_over = Thread::Queue.new
          @response = nil
          @switched = false
          @finished = false
        end

        def buffer(string)
          buffer = IO::Buffer.for(string)
          @buffers << buffer
          buffer
        end

        def invoke(app, request)
          @call_fiber = Fiber.current
          response = app.call(request)
        ensure
          @call_fiber = nil
          @returned = true
          @buffers.each(&:free)
          hand_over(response) unless response.respond_to?(:call)
        end

        def invoke_deferred(deferred)
          @call_fiber = Fiber.current
          deferred.call(lambda do |response|
            raise SpecError, "responder called after the response has been handed over" if handed_over?
            hand_over(response)
          end)
        ensure
          @call_fiber = nil
        end

        def raise_if_from_call(name)
          raise SpecError, "#{name} called from #call" if Fiber.current == @call_fiber
        end

        def raise_if_returned(name)
          raise SpecError, "#{name} called after #call has returned" if @returned
        end

        def handed_over?
          @handed_over.closed?
        end

        def wait_until_handed_over
          @handed_over.pop
        end

        def response
          wait_until_handed_over
          @response
        end

        def switched?
          @switched
        end

        def finish
          @finished = true
          @buffers.each(&:free)
          @handed_over.close
        end

        def raise_if_finished(name)
          raise SpecError, "#{name} called after the host has finished with the response" if @finished
        end

        private

        def hand_over(response)
          @response = response
          status, headers = response if response.is_a?(Array)
          @switched = switches?(status, headers)
          @handed_over.close
        end

        def upgrades(headers)
          headers.filter_map { |name, value| value if name == "upgrade" }.flat_map { it.split(",") }.map { it.strip.downcase }
        end

        def switches?(status, headers)
          if status == 101
            @http_version == "HTTP/1.1" && !(protocols = upgrades(headers)).empty? && (protocols - upgrades(@headers)).empty?
          else
            @method == "CONNECT" && (200..299).cover?(status)
          end
        end
      end
      private_constant :Exchange

      class Stream
        def initialize(exchange, chunks, condition, &on_end)
          @exchange = exchange
          @chunks = chunks
          @condition = condition
          @on_end = on_end
          @index = 0
        end

        def read
          @exchange.raise_if_finished(:read)
          next_chunk
        end

        private

        def next_chunk
          @buffer&.free
          if @index < @chunks.size
            @buffer = @exchange.buffer(@chunks[@index])
            @index += 1
            @buffer.slice
          elsif @condition
            raise Error, @condition
          else
            @on_end&.call
            nil
          end
        end
      end
      private_constant :Stream

      class Tunnel < Stream
        def read
          @exchange.raise_if_finished(:read)
          @exchange.raise_if_from_call(:read)
          @exchange.wait_until_handed_over
          raise Error, :tunnel_not_switched unless @exchange.switched?
          next_chunk
        end
      end
      private_constant :Tunnel

      class Request
        TARGET = %r{\A(?:[A-Za-z][0-9A-Za-z+\-.]*://([^/?#]*)|(?=/))(/[^\s\0?#]*)?(?:\?([^\s\0#]*))?\z}

        def initialize(exchange, method, target, http_version:, headers:, scheme: "http", remote_address: nil, remote_port: nil,
          local_address: nil, local_port: nil, connection: {}, protocol: nil, content_length: nil, variables: {}, body: [], body_error: nil,
          trailers: [], decline_informs: false, tunnel: [], tunnel_error: nil, &on_inform)
          if protocol && !(method == "CONNECT" && %w[HTTP/2 HTTP/3].include?(http_version))
            raise ArgumentError, "protocol given for a #{method} request over #{http_version}"
          end
          valid = if method == "CONNECT" && protocol.nil?
            authority = target
            Spec.valid_authority?(authority) && authority.match?(/:\d*\z/)
          elsif target == "*"
            path = target
            method == "OPTIONS"
          elsif (match = TARGET.match(target))
            authority, path, query = match.captures
            path ||= (method == "OPTIONS" && query.nil?) ? "*" : "/"
            query = nil if query == ""
            authority.nil? || Spec.valid_authority?(authority)
          end
          valid or raise ArgumentError, "invalid request target: #{target.inspect}"
          headers.each { |field| valid_field?(field) or raise ArgumentError, "invalid header field: #{field.inspect}" }
          if %w[HTTP/2 HTTP/3].include?(http_version) && (cookies = headers.select { |name,| name == "cookie" }).size > 1
            headers = headers - cookies + [["cookie", cookies.map(&:last).join("; ")]]
          end
          hosts, headers = headers.partition { |name,| name == "host" }
          raise ArgumentError, "more than one host given" if hosts.size > 1
          if (host = hosts.dig(0, 1)) && !host.empty?
            Spec.valid_authority?(host) or raise ArgumentError, "invalid host: #{host.inspect}"
            authority ||= host
          end
          %w[content-length transfer-encoding].each { |name| raise ArgumentError, "#{name} given as a header" if headers.assoc(name) }
          trailers.each { |field| valid_field?(field) or raise ArgumentError, "invalid trailer field: #{field.inspect}" }
          @exchange = exchange
          @scheme = scheme
          @http_version = http_version
          @remote_address = remote_address
          @remote_port = remote_port
          @local_address = local_address
          @local_port = local_port
          @connection = connection
          @request_method = method
          @protocol = protocol
          @authority = authority
          @path = path
          @query = query
          @headers = headers
          @content_length = content_length
          @variables = variables
          @body = Stream.new(exchange, body, body_error) { @body_ended = true }
          @body_ended = false
          @trailers = trailers
          @decline_informs = decline_informs
          @on_inform = on_inform
          @tunnel = Tunnel.new(exchange, tunnel, tunnel_error)
        end

        def scheme
          @exchange.raise_if_returned(:scheme)
          @scheme
        end

        def http_version
          @exchange.raise_if_returned(:http_version)
          @http_version
        end

        def remote_address
          @exchange.raise_if_returned(:remote_address)
          @remote_address
        end

        def remote_port
          @exchange.raise_if_returned(:remote_port)
          @remote_port
        end

        def local_address
          @exchange.raise_if_returned(:local_address)
          @local_address
        end

        def local_port
          @exchange.raise_if_returned(:local_port)
          @local_port
        end

        def connection
          @exchange.raise_if_returned(:connection)
          @connection
        end

        def request_method
          @exchange.raise_if_returned(:request_method)
          @exchange.buffer(@request_method).slice
        end

        def protocol
          @exchange.raise_if_returned(:protocol)
          @protocol && @exchange.buffer(@protocol).slice
        end

        def authority
          @exchange.raise_if_returned(:authority)
          @authority && @exchange.buffer(@authority).slice
        end

        def path
          @exchange.raise_if_returned(:path)
          @path && @exchange.buffer(@path).slice
        end

        def query
          @exchange.raise_if_returned(:query)
          @query && @exchange.buffer(@query).slice
        end

        def headers
          @exchange.raise_if_returned(:headers)
          @headers.map { |field| field.map { @exchange.buffer(it).slice } }
        end

        def content_length
          @exchange.raise_if_returned(:content_length)
          @content_length
        end

        def variable(name)
          @exchange.raise_if_finished(:variable)
          @variable&.free
          @variable = (value = @variables[name]) && @exchange.buffer(value)
          @variable&.slice
        end

        def body
          @exchange.raise_if_finished(:body)
          @body
        end

        def trailers
          @exchange.raise_if_finished(:trailers)
          raise Error, :trailers_incomplete unless @body_ended
          @trailer_buffers&.each { |field| field.each(&:free) }
          @trailer_buffers = @trailers.map { |field| field.map { @exchange.buffer(it) } }
          @trailer_buffers.map { |field| field.map(&:slice) }
        end

        def inform(status, headers)
          @exchange.raise_if_finished(:inform)
          raise Error, :inform_responded if @exchange.handed_over?
          raise Error, :inform_invalid unless valid_interim_response?(status, headers)
          return false if @decline_informs
          @on_inform.call(status, Headers.new(headers).delete("content-length"))
          true
        end

        def tunnel
          @exchange.raise_if_finished(:tunnel)
          @tunnel
        end

        private

        def valid_field?(field)
          field.is_a?(Array) && field.size == 2 && Spec.valid_header_name?(field[0]) && Spec.valid_header_value?(field[1])
        end

        def valid_interim_response?(status, headers)
          Spec.valid_interim_status?(status) && headers.is_a?(Array) &&
            headers.all? { |field| valid_field?(field) && !Spec.connection_header?(field[0], status) }
        end
      end
      private_constant :Request

      def initialize(app)
        @app = app
      end

      def request(method, target, http_version: "HTTP/1.1", headers: [], cancel: false, **options)
        exchange = Exchange.new(method, http_version, headers)
        interim_responses = []
        request = Request.new(exchange, method, target, http_version:, headers:, **options) { |status, fields| interim_responses << [status, fields] }
        response = exchange.invoke(@app, request)
        if response.respond_to?(:call)
          exchange.invoke_deferred(response)
          response.cancel if cancel && response.respond_to?(:cancel)
          response = exchange.response
          raise response if response.is_a?(Exception)
        end
        status, response_headers, body = response
        if status == 101 && !exchange.switched?
          body.close if body.respond_to?(:close)
          raise SpecError, "101 does not switch to a tunnel"
        end
        content, trailers = read_body(body)
        Response.new(status:, headers: Headers.new(response_headers), body: content, trailers: Headers.new(trailers), interim_responses:)
      ensure
        exchange.finish
      end

      private

      def read_body(body)
        case body
        when nil, String, IO::Buffer then return [Utils.read_body(body).b, []]
        end
        content = "".b
        body.each { |chunk| content.append_as_bytes(chunk.is_a?(IO::Buffer) ? chunk.get_string : chunk.to_str) }
        [content, body.respond_to?(:trailers) ? body.trailers : []]
      ensure
        body.close if body.respond_to?(:close)
      end
    end
  end
end
