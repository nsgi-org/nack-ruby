# frozen_string_literal: true

require_relative "helper"

describe Nack::Request do
  def request(**fields)
    source = fields.to_h do |name, value|
      case name
      when :request_method, :authority, :path, :query then [name, value && IO::Buffer.for(value)]
      when :headers then [name, value.map { |field| field.map { IO::Buffer.for(it) } }]
      else [name, value]
      end
    end
    Nack::Request.new(Struct.new(*source.keys).new(*source.values))
  end

  def stream(*chunks)
    Object.new.tap do |stream|
      stream.define_singleton_method(:read) { (chunk = chunks.shift) && IO::Buffer.for(chunk) }
    end
  end

  it "reads the scheme and peer the bridge supplies" do
    req = request(scheme: "https", remote_address: "::1", headers: [["x-forwarded-proto", "http"], ["x-forwarded-for", "1.1.1.1"]])
    req.scheme.must_equal "https"
    req.ssl?.must_equal true
    req.remote_address.must_equal "::1"
    request(scheme: nil).ssl?.must_equal false
  end

  it "reads the host and port from the authority" do
    request(scheme: "http", authority: "a:65535").then { [it.host, it.port] }.must_equal ["a", 65535]
    request(scheme: "http", authority: "a").then { [it.host, it.port] }.must_equal ["a", 80]
    request(scheme: nil, authority: "a").then { [it.host, it.port] }.must_equal ["a", nil]
    request(scheme: "https", authority: "a:").then { [it.host, it.port] }.must_equal ["a", 443]
    request(scheme: "http", authority: "[::1]:1").then { [it.host, it.port] }.must_equal ["[::1]", 1]
    request(scheme: "http", authority: "[::1]").then { [it.host, it.port] }.must_equal ["[::1]", 80]
    request(scheme: "http", authority: "a:65536").then { [it.host, it.port] }.must_equal [nil, nil]
    request(scheme: "http", authority: "a:b").then { [it.host, it.port] }.must_equal [nil, nil]
    request(scheme: "http", authority: "[::1").then { [it.host, it.port] }.must_equal [nil, nil]
    request(authority: nil).then { [it.host, it.port] }.must_equal [nil, nil]
  end

  it "reads the method, path and query" do
    req = request(request_method: "GET", path: "/a", query: "b")
    req.request_method.must_equal "GET"
    req.script_name.must_equal ""
    req.path_info.must_equal "/a"
    req.query_string.must_equal "b"
    [req.request_method, req.path_info, req.query_string].each { it.must_be :frozen? }
    request(path: nil, query: nil).then { [it.path_info, it.query_string] }.must_equal ["", ""]
    request(path: "*").path_info.must_equal "*"
  end

  it "rewrites fields" do
    req = request
    body = stream
    req.request_method = "PUT"
    req.script_name = "/a"
    req.path_info = "/b"
    req.query_string = "c"
    req.headers = Nack::Headers.new([["d", "1"]])
    req.body = body
    req.request_method.must_equal "PUT"
    req.script_name.must_equal "/a"
    req.path_info.must_equal "/b"
    req.query_string.must_equal "c"
    req.headers["d"].must_equal "1"
    req.body.must_be_same_as body
  end

  it "reads headers as Nack::Headers" do
    values = request(headers: [["a", "1"], ["a", "2"]]).headers.get_all("a")
    values.must_equal ["1", "2"]
    values.each { it.must_be :frozen? }
  end

  it "reads the content type" do
    req = request(headers: [["content-type", "Text/HTML ; charset=utf-8"]])
    req.content_type.must_equal "Text/HTML ; charset=utf-8"
    req.media_type.must_equal "text/html"
    request(headers: []).media_type.must_be_nil
  end

  it "parses cookies as sent, the first of a name winning" do
    request(headers: [["cookie", "a=1; b=+%20=;;c=3; a=2; d"]]).cookies.must_equal({"a" => "1", "b" => "+%20=", "c" => "3", "" => "d"})
  end

  it "parses the query and a form body" do
    req = request(query: "a=1&b=2", headers: [["content-type", "application/x-www-form-urlencoded; charset=utf-8"]], body: stream("b=3&", "c=4"))
    req.GET.must_equal({"a" => "1", "b" => "2"})
    req.POST.must_equal({"b" => "3", "c" => "4"})
    req.params.must_equal({"a" => "1", "b" => "3", "c" => "4"})
  end

  it "leaves any other body unread" do
    req = request(headers: [["content-type", "text/plain"]], body: stream("a=1"))
    req.POST.must_equal({})
    req.body.read.get_string.must_equal "a=1"
  end

  it "reparses after a rewrite" do
    req = request(query: "a=1", headers: [], body: stream)
    req.params.must_equal({"a" => "1"})
    req.query_string = "a=2"
    req.GET.must_equal({"a" => "2"})
    req.headers = Nack::Headers.new([["content-type", "application/x-www-form-urlencoded"]])
    req.body = stream("b=3")
    req.params.must_equal({"a" => "2", "b" => "3"})
    req.cookies.must_equal({})
    req.headers["cookie"] = "c=4"
    req.cookies.must_equal({"c" => "4"})
  end

  it "passes the rest through from the bridge" do
    connection = {}
    protocol = IO::Buffer.for("websocket")
    authority = IO::Buffer.for("a")
    trailers = []
    tunnel = stream
    source = Struct.new(:connection, :protocol, :authority, :content_length, :trailers, :tunnel) do
      def variable(name) = [:variable, name]
      def inform(status, headers) = [:inform, status, headers]
    end.new(connection, protocol, authority, 1, trailers, tunnel)
    req = Nack::Request.new(source)
    req.connection.must_be_same_as connection
    req.protocol.must_be_same_as protocol
    req.authority.must_be_same_as authority
    req.content_length.must_equal 1
    req.variable("a").must_equal [:variable, "a"]
    req.trailers.must_be_same_as trailers
    req.inform(103, []).must_equal [:inform, 103, []]
    req.tunnel.must_be_same_as tunnel
  end

  it "keeps a context" do
    req = request
    req.context[:a] = 1
    req.context.must_equal({a: 1})
  end
end
