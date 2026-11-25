# frozen_string_literal: true

require_relative "helper"
require "nack/handler/mock"

describe Nack::Handler::Mock do
  def observe(method, target, **options)
    observed = nil
    app = lambda do |request|
      observed = yield(request)
      [200, [], nil]
    end
    Nack::Handler::Mock.new(app).request(method, target, **options)
    observed
  end

  def respond(method = "GET", target = "/", **options, &app)
    Nack::Handler::Mock.new(app).request(method, target, **options)
  end

  it "builds a request from an origin-form target" do
    observe("GET", "/a?b") do |request|
      [request.request_method.get_string, request.authority, request.path.get_string, request.query.get_string]
    end.must_equal ["GET", nil, "/a", "b"]
    observe("GET", "/a?") { it.query }.must_be_nil
    observe("GET", "/", headers: [["host", "a"]]) { [it.authority.get_string, it.headers] }.must_equal ["a", []]
    observe("GET", "/", headers: [["host", ""]]) { it.authority }.must_be_nil
  end

  it "builds a request from an absolute-form target, keeping the scheme of the hop and ignoring the host" do
    observe("GET", "https://a", headers: [["host", "b"]]) do
      [it.scheme, it.authority.get_string, it.path.get_string, it.query]
    end.must_equal ["http", "a", "/", nil]
  end

  it "gives an absolute-form target with an empty path a path of * only for an OPTIONS request carrying no query" do
    ["http://a", "http://a?"].map { |target| observe("OPTIONS", target) { it.path.get_string } }.must_equal ["*", "/"]
  end

  it "builds a request from an authority-form or asterisk-form target" do
    observe("CONNECT", "a:1") { [it.authority.get_string, it.path, it.query] }.must_equal ["a:1", nil, nil]
    observe("OPTIONS", "*") { [it.authority, it.path.get_string] }.must_equal [nil, "*"]
  end

  it "accepts a protocol that is message text only on an HTTP/2 or HTTP/3 CONNECT request" do
    %w[HTTP/2 HTTP/3].map do |http_version|
      observe("CONNECT", "https://a/b", http_version:, protocol: "websocket") { [it.protocol.get_string, it.path.get_string] }
    end.must_equal [["websocket", "/b"]] * 2
    [["CONNECT", "HTTP/1.1"], ["GET", "HTTP/2"]].each do |method, http_version|
      -> { respond(method, "https://a/b", http_version:, protocol: "websocket") }.must_raise ArgumentError
    end
    -> { respond("CONNECT", "https://a/b", http_version: "HTTP/2", protocol: " a") }.must_raise ArgumentError
  end

  it "rejects an invalid request target" do
    ["?a", "http://u@a", "/ ", "/\0", "/? ", "/?\0", "/#a"].each { |target| -> { respond("GET", target) }.must_raise ArgumentError }
    [":1", "a"].each { |target| -> { respond("CONNECT", target) }.must_raise ArgumentError }
    -> { respond("GET", "*") }.must_raise ArgumentError
  end

  it "rejects an invalid host, even one the target overrides, and a second host" do
    -> { respond("GET", "http://a", headers: [["host", "u@a"]]) }.must_raise ArgumentError
    -> { respond("GET", "/", headers: [["host", "a"], ["host", "a"]]) }.must_raise ArgumentError
  end

  it "joins the cookie fields of an HTTP/2 or HTTP/3 request, leaving a single one in place" do
    fields = [["cookie", "a"], ["b", "1"], ["cookie", "c"]]
    [["HTTP/1.1", fields], ["HTTP/2", fields], ["HTTP/3", fields], ["HTTP/2", fields[0, 2]]].map do |http_version, headers|
      observe("GET", "/", http_version:, headers:) { |request| request.headers.map { |field| field.map(&:get_string) } }
    end.must_equal [fields, [["b", "1"], ["cookie", "a; c"]], [["b", "1"], ["cookie", "a; c"]], fields[0, 2]]
  end

  it "rejects an invalid header field, content-length or transfer-encoding" do
    [[":a", "1"], ["content-length", "0"], ["transfer-encoding", "chunked"]].each do |field|
      -> { respond("GET", "/", headers: [field]) }.must_raise ArgumentError
    end
  end

  it "passes the options to the request" do
    connection = {}
    observe("GET", "/", scheme: "https", http_version: "HTTP/2", remote_address: "::1", remote_port: 3, local_address: "::2", local_port: 5,
      connection:, headers: [["a", "1"]], content_length: 2, variables: {"b" => "4"}) do |request|
      [request.scheme, request.http_version, request.remote_address, request.remote_port, request.local_address, request.local_port, request.connection,
        request.headers.map { |field| field.map(&:get_string) }, request.content_length, request.variable("b").get_string, request.variable("c")]
    end.must_equal ["https", "HTTP/2", "::1", 3, "::2", 5, connection, [["a", "1"]], 2, "4", nil]
  end

  it "accepts no scheme, and each HTTP version SPEC.md section 3 names or none" do
    observe("GET", "/", scheme: nil) { it.scheme }.must_be_nil
    versions = [nil, "HTTP/1.0", "HTTP/1.1", "HTTP/2", "HTTP/3"]
    versions.map { |http_version| observe("GET", "/", http_version:) { it.http_version } }.must_equal versions
  end

  it "rejects an invalid scheme, HTTP version or method" do
    -> { respond("GET", "/", scheme: "A") }.must_raise ArgumentError
    -> { respond("GET", "/", http_version: "HTTP/2.0") }.must_raise ArgumentError
    -> { respond("", "/") }.must_raise ArgumentError
  end

  it "exposes only the methods SPEC.md section 3 gives the request and its streams" do
    observe("GET", "/") do |request|
      [request, request.body, request.tunnel].map { (it.public_methods - Object.public_instance_methods).sort }
    end.must_equal [%i[scheme http_version remote_address remote_port local_address local_port connection request_method protocol authority
      path query headers content_length variable body trailers inform tunnel].sort, [:read], [:read]]
  end

  it "delivers the body, then ends it or fails it with the condition given as a StandardError outside Nack::Error" do
    observe("POST", "/", body: ["a"]) { |request| [request.body.read.get_string, request.body.read, request.body.read] }.must_equal ["a", nil, nil]
    errors = observe("POST", "/", body: ["a"], body_error: :body_timeout) do |request|
      request.body.read
      2.times.map { -> { request.body.read }.must_raise Nack::Handler::Mock::Error }
    end
    errors.map { [it.condition, it.is_a?(StandardError), it.is_a?(Nack::Error)] }.must_equal [[:body_timeout, true, false]] * 2
  end

  it "rejects a zero-length body or tunnel chunk" do
    -> { respond("POST", "/", body: [""]) }.must_raise ArgumentError
    -> { respond("CONNECT", "a:1", tunnel: [""]) }.must_raise ArgumentError
  end

  it "raises :trailers_incomplete until the body has ended" do
    observe("POST", "/", trailers: [["a", "1"]]) do |request|
      condition = (-> { request.trailers }.must_raise Nack::Handler::Mock::Error).condition
      request.body.read
      [condition, request.trailers.map { |field| field.map(&:get_string) }]
    end.must_equal [:trailers_incomplete, [["a", "1"]]]
  end

  it "rejects an invalid trailer field" do
    -> { respond("POST", "/", trailers: [[":a", "1"]]) }.must_raise ArgumentError
  end

  it "reads the response, its body to the end, and its trailers before closing it" do
    [nil, "é", IO::Buffer.for("é")].map { |content| respond { [200, [], content] }.body }.must_equal ["", "é".b, "é".b]
    respond { [200, [], nil] }.body.encoding.must_equal Encoding::BINARY
    calls = []
    body = Struct.new(:calls) do
      def each
        calls << :each
        yield "a"
        yield IO::Buffer.for("é")
      end

      def trailers
        calls << :trailers
        [["b", "1"]]
      end

      def close
        calls << :close
      end
    end.new(calls)
    response = respond { [201, [["c", "2"]], body] }
    [response.status, response.headers.to_a, response.body, response.trailers.to_a].must_equal [201, [["c", "2"]], "aé".b, [["b", "1"]]]
    calls.must_equal [:each, :trailers, :close]
    -> { respond { [200, [], [1]] } }.must_raise NoMethodError
  end

  it "closes the body when enumerating it raises" do
    calls = []
    body = Struct.new(:calls) do
      def each
        raise StandardError
      end

      def close
        calls << :close
      end
    end.new(calls)
    -> { respond { [200, [], body] } }.must_raise StandardError
    calls.must_equal [:close]
  end

  it "hands over the response a deferred response passes its responder, raising SpecError for a second call and leaving the first in effect" do
    respond { ->(responder) { Thread.new { responder.call([201, [], nil]) } } }.status.must_equal 201
    respond do
      lambda do |responder|
        responder.call([201, [], nil])
        -> { responder.call([202, [], nil]) }.must_raise Nack::SpecError
      end
    end.status.must_equal 201
  end

  it "calls #cancel on a deferred response that responds to it, given cancel:, once its #call has returned" do
    calls = []
    deferred = Struct.new(:calls, :responding) do
      def call(responder)
        @responder = responder
        responding.call(responder)
        calls << :returned
      end

      def cancel
        calls << :cancel
        @responder.call([200, [], nil])
      end
    end
    later = ->(responder) { Thread.new { responder.call([200, [], nil]) } }
    respond(cancel: true) { deferred.new(calls, ->(_) {}) }
    respond(cancel: true) { later }
    respond { deferred.new(calls, later) }
    calls.must_equal [:returned, :cancel, :returned]
  end

  it "records the interim responses it accepts, leaving out content-length" do
    response = respond { |request| [200, [], request.inform(103, [["a", "1"], ["content-length", "0"]]).to_s] }
    [response.body, response.interim_responses.map { |status, headers| [status, headers.to_a] }].must_equal ["true", [[103, [["a", "1"]]]]]
    response = respond(decline_informs: true) { |request| [200, [], request.inform(103, []).to_s] }
    [response.body, response.interim_responses].must_equal ["false", []]
  end

  it "raises :inform_invalid for an invalid interim response, and :inform_responded once the response is handed over" do
    observe("GET", "/") do |request|
      [[101, []], [103, nil], [103, ["a1"]], [103, [["a", "1", "2"]]], [103, [["A", "1"]]], [103, [["a", "\n"]]], [103, [["connection", "close"]]]]
        .map { |status, headers| (-> { request.inform(status, headers) }.must_raise Nack::Handler::Mock::Error).condition }
    end.must_equal [:inform_invalid] * 7
    error = -> { respond { |request| [200, [], Enumerator.new { request.inform(103, []) }] } }.must_raise Nack::Handler::Mock::Error
    error.condition.must_equal :inform_responded
  end

  it "switches a 101 only for an HTTP/1.1 request listing every protocol its upgrade names, raising SpecError otherwise" do
    respond("GET", "/", headers: [["upgrade", "a"], ["upgrade", "b, c"]]) { [101, [["upgrade", "C"]], nil] }.status.must_equal 101
    [["HTTP/2", [["upgrade", "a"]], [["upgrade", "a"]]], ["HTTP/1.1", [], [["upgrade", "a"]]], ["HTTP/1.1", [["upgrade", "a"]], []],
      ["HTTP/1.1", [["upgrade", "a"]], [["upgrade", "a, b"]]]].each do |http_version, headers, response_headers|
      -> { respond("GET", "/", http_version:, headers:) { [101, response_headers, nil] } }.must_raise Nack::SpecError
    end
  end

  it "closes the body of a 101 that does not switch without enumerating it" do
    calls = []
    body = Struct.new(:calls) do
      def each
        calls << :each
      end

      def close
        calls << :close
      end
    end.new(calls)
    -> { respond { [101, [], body] } }.must_raise Nack::SpecError
    calls.must_equal [:close]
  end

  it "delivers the tunnel once a switching response is handed over, then fails it with the condition given" do
    response = respond("GET", "/", headers: [["upgrade", "b"]], tunnel: ["a"]) do |request|
      reader = Thread.new { request.tunnel.read.get_string }
      Thread.pass until reader.stop?
      [101, [["upgrade", "b"]], Enumerator.new { it << reader.value }]
    end
    response.body.must_equal "a"
    conditions = []
    response = respond("CONNECT", "a:1", tunnel: ["b"], tunnel_error: :tunnel_timeout) do |request|
      [200, [], Enumerator.new do |chunks|
        chunks << request.tunnel.read.get_string
        2.times { conditions << (-> { request.tunnel.read }.must_raise Nack::Handler::Mock::Error).condition }
      end]
    end
    [response.body, conditions].must_equal ["b", [:tunnel_timeout, :tunnel_timeout]]
    respond("CONNECT", "a:1", tunnel: ["c"]) do |request|
      ->(responder) { responder.call([200, [], Enumerator.new { it << request.tunnel.read.get_string }]) }
    end.body.must_equal "c"
  end

  it "raises :tunnel_terminated for a tunnel read once the host has aborted the tunnel" do
    tunnel = nil
    respond("CONNECT", "a:1") do |request|
      tunnel = request.tunnel
      [200, [], nil]
    end
    (-> { tunnel.read }.must_raise Nack::Handler::Mock::Error).condition.must_equal :tunnel_terminated
  end

  it "raises SpecError for a tunnel read from #call or a deferred response's #call" do
    -> { respond { |request| request.tunnel.read } }.must_raise Nack::SpecError
    -> { respond { |request| ->(_) { request.tunnel.read } } }.must_raise Nack::SpecError
  end

  it "raises :tunnel_not_switched for a response that does not switch, including once #call or a deferred response raises" do
    [["GET", "/", 200], ["CONNECT", "a:1", 300]].each do |method, target, status|
      error = -> { respond(method, target) { |request| [status, [], Enumerator.new { request.tunnel.read }] } }.must_raise Nack::Handler::Mock::Error
      error.condition.must_equal :tunnel_not_switched
    end
    readers = []
    raising = lambda do |request|
      readers << Thread.new do
        request.tunnel.read
      rescue Nack::Handler::Mock::Error => exception
        exception.condition
      end
      Thread.pass until readers.last.stop?
      raise StandardError
    end
    -> { respond(&raising) }.must_raise StandardError
    -> { respond { |request| ->(_) { raising.call(request) } } }.must_raise StandardError
    readers.map(&:value).must_equal [:tunnel_not_switched] * 2
  end

  it "accepts only a condition SPEC.md gives a failed body or tunnel" do
    %i[body_terminated body_malformed body_too_large body_timeout].map { |body_error| respond("POST", "/", body_error:) { [200, [], nil] }.status }
      .must_equal [200] * 4
    %i[tunnel_terminated tunnel_timeout].map { |tunnel_error| respond("CONNECT", "a:1", tunnel_error:) { [200, [], nil] }.status }.must_equal [200] * 2
    -> { respond("POST", "/", body_error: :trailers_incomplete) }.must_raise ArgumentError
    -> { respond("CONNECT", "a:1", tunnel_error: :tunnel_not_switched) }.must_raise ArgumentError
  end

  it "hands out read-only buffers" do
    -> { observe("GET", "/") { it.path.set_string("a") } }.must_raise IO::Buffer::AccessError
  end

  it "invalidates a buffer obtained while #call runs once #call has returned" do
    respond("GET", "/", variables: {"a" => "1"}) do |request|
      variable = request.variable("a")
      [200, [], Enumerator.new { -> { variable.get_string }.must_raise IO::Buffer::InvalidatedError }]
    end
  end

  it "invalidates a chunk, variable or trailer at the next call of its accessor" do
    observe("POST", "/", body: ["a", "b"], trailers: [["c", "1"]], variables: {"d" => "2"}) do |request|
      chunk = request.body.read
      request.body.read
      -> { chunk.get_string }.must_raise IO::Buffer::InvalidatedError
      request.body.read
      trailer = request.trailers.first.first
      request.trailers
      -> { trailer.get_string }.must_raise IO::Buffer::InvalidatedError
      variable = request.variable("d")
      request.variable("d")
      -> { variable.get_string }.must_raise IO::Buffer::InvalidatedError
    end
  end

  it "invalidates every buffer once the host has finished with the response" do
    chunk = nil
    respond("POST", "/", body: ["a"]) { |request| [200, [], Enumerator.new { chunk = request.body.read }] }
    -> { chunk.get_string }.must_raise IO::Buffer::InvalidatedError
  end

  it "raises SpecError for an accessor or stream called once it is no longer usable" do
    request = streams = nil
    respond do
      request = it
      streams = [it.body, it.tunnel]
      [200, [], nil]
    end
    streams.each { |stream| -> { stream.read }.must_raise Nack::SpecError }
    %i[scheme http_version remote_address remote_port local_address local_port connection request_method protocol authority path
      query headers content_length body trailers tunnel].each { |name| -> { request.public_send(name) }.must_raise Nack::SpecError }
    -> { request.variable("a") }.must_raise Nack::SpecError
    -> { request.inform(103, []) }.must_raise Nack::SpecError
  end

  it "reraises an exception raised from #call or passed to a deferred response's responder" do
    error = StandardError.new
    (-> { respond { raise error } }.must_raise StandardError).must_be_same_as error
    (-> { respond { ->(responder) { responder.call(error) } } }.must_raise StandardError).must_be_same_as error
  end
end
