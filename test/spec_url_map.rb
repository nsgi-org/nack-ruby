# frozen_string_literal: true

require_relative "helper"

describe Nack::URLMap do
  def request(path:, authority: nil)
    Nack::Request.new(Struct.new(:scheme, :authority, :path).new(nil, authority && IO::Buffer.for(authority), path && IO::Buffer.for(path)))
  end

  def app(name)
    ->(request) { [name, request.script_name, request.path_info] }
  end

  it "rejects a reference without a leading slash or host, or with a port" do
    ["a", "///a", "//h:/", "//h:1"].each { |reference| -> { Nack::URLMap.new(reference => app(:a)) }.must_raise ArgumentError }
  end

  it "rejects references naming the same mount, ignoring host case and a trailing slash" do
    [["/a", "/a/"], ["//h/a", "//H/a"]].each { |references| -> { Nack::URLMap.new(references.to_h { [it, app(:a)] }) }.must_raise ArgumentError }
    Nack::URLMap.new("/a" => app(:a), "//h/a" => app(:h)).call(request(authority: "h", path: "/a")).first.must_equal :h
  end

  it "matches no prefix against authority-form and asterisk-form" do
    map = Nack::URLMap.new("/" => app(:root))
    [request(path: nil), request(path: "*")].each { map.call(it).first.must_equal 404 }
  end

  it "moves the longest prefix ending at a segment boundary from path_info to script_name" do
    map = Nack::URLMap.new("/" => app(:root), "/a" => app(:a), "/a/b/" => app(:ab))
    map.call(request(path: "/a/b/c")).must_equal [:ab, "/a/b", "/c"]
    map.call(request(path: "/a/bc")).must_equal [:a, "/a", "/bc"]
    map.call(request(path: "/a")).must_equal [:a, "/a", ""]
    map.call(request(path: "/b")).must_equal [:root, "", "/b"]
  end

  it "prefers a mount for the host, ignoring case and port, over a longer prefix" do
    map = Nack::URLMap.new("/a/b" => app(:ab), "//h/a" => app(:h))
    map.call(request(authority: "H:1", path: "/a/b")).must_equal [:h, "/a", "/b"]
    map.call(request(authority: "i", path: "/a/b")).must_equal [:ab, "/a/b", ""]
    map.call(request(path: "/a/b")).must_equal [:ab, "/a/b", ""]
    Nack::URLMap.new("//[::1]" => app(:h)).call(request(authority: "[::1]:1", path: "/")).must_equal [:h, "", "/"]
    Nack::URLMap.new("//é" => app(:h)).call(request(authority: "é", path: "/")).must_equal [:h, "", "/"]
  end

  it "responds 404 when no prefix matches" do
    Nack::URLMap.new("/a" => app(:a)).call(request(path: "/b")).must_equal [404, [["content-type", "text/plain"]], "Not Found"]
  end

  it "appends to script_name when nested, matching after an outer mount took the whole path" do
    Nack::URLMap.new("/a" => Nack::URLMap.new("/b" => app(:b))).call(request(path: "/a/b/c")).must_equal [:b, "/a/b", "/c"]
    Nack::URLMap.new("/a" => Nack::URLMap.new("/" => app(:root))).call(request(path: "/a")).must_equal [:root, "/a", ""]
  end

  it "restores script_name and path_info after the mounted app returns or raises" do
    req = request(path: "/a/b")
    Nack::URLMap.new("/a" => app(:a)).call(req)
    [req.script_name, req.path_info].must_equal ["", "/a/b"]
    -> { Nack::URLMap.new("/a" => ->(_) { raise }).call(req) }.must_raise RuntimeError
    [req.script_name, req.path_info].must_equal ["", "/a/b"]
  end
end
