# frozen_string_literal: true

require_relative "helper"

describe Nack::Response do
  it "sets and deletes the content type, content length and location" do
    res = Nack::Response.new
    res.content_type = "a"
    res.content_length = 1
    res.location = "b"
    [res.content_type, res.content_length, res.location].must_equal ["a", 1, "b"]
    res.content_type = nil
    res.content_length = nil
    res.location = nil
    res.headers.to_a.must_equal []
  end

  it "reads no content length from a malformed field" do
    Nack::Response.new(200, [["content-length", "-1"]]).content_length.must_be_nil
  end

  it "rejects a content length other than a non-negative Integer" do
    res = Nack::Response.new
    -> { res.content_length = -1 }.must_raise Nack::SpecError
    -> { res.content_length = "1" }.must_raise Nack::SpecError
    res.content_length = 0
    res.headers.to_a.must_equal [["content-length", "0"]]
  end

  it "redirects" do
    res = Nack::Response.new
    res.redirect("a")
    [res.status, res.location].must_equal [302, "a"]
    res.redirect("b", 301)
    [res.status, res.location].must_equal [301, "b"]
  end

  it "rejects a cookie outside the rfc6265bis grammar" do
    res = Nack::Response.new
    -> { res.set_cookie("", "1") }.must_raise ArgumentError
    -> { res.set_cookie("a=a", "1") }.must_raise ArgumentError
    -> { res.set_cookie("a", "1;") }.must_raise ArgumentError
    -> { res.set_cookie("a", "\"1") }.must_raise ArgumentError
    -> { res.set_cookie("a", "1", expires: Time.new(1900, 1, 1, 8, 59, 59, "+09:00")) }.must_raise ArgumentError
    -> { res.set_cookie("a", "1", expires: Time.utc(10000)) }.must_raise ArgumentError
    -> { res.set_cookie("a", "1", max_age: 0) }.must_raise ArgumentError
    -> { res.set_cookie("a", "1", max_age: "1") }.must_raise ArgumentError
    -> { res.set_cookie("a", "1", domain: ".b") }.must_raise ArgumentError
    -> { res.set_cookie("a", "1", domain: "-b") }.must_raise ArgumentError
    -> { res.set_cookie("a", "1", domain: "b-") }.must_raise ArgumentError
    -> { res.set_cookie("a", "1", domain: "b" * 64) }.must_raise ArgumentError
    -> { res.set_cookie("a", "1", path: ";") }.must_raise ArgumentError
    -> { res.set_cookie("a", "1", path: "é") }.must_raise ArgumentError
    -> { res.set_cookie("a", "1", same_site: "LaxLax") }.must_raise ArgumentError
    res.headers.to_a.must_equal []
  end

  it "sets cookies" do
    res = Nack::Response.new
    res.set_cookie("a", "\"1\"")
    res.set_cookie("b", "", expires: Time.new(1900, 1, 1, 9, 0, 0, "+09:00"), max_age: 1, domain: "0-a.b", path: "a b", secure: true, http_only: true, same_site: "Lax")
    res.set_cookie("c", "", expires: Time.utc(9999), domain: "b" * 63)
    res.headers.get_all("set-cookie").must_equal [
      "a=\"1\"",
      "b=; expires=Mon, 01 Jan 1900 00:00:00 GMT; max-age=1; domain=0-a.b; path=a b; secure; httponly; samesite=Lax",
      "c=; expires=Fri, 01 Jan 9999 00:00:00 GMT; domain=#{"b" * 63}"
    ]
  end

  it "replaces a cookie of the same name, keeping the other fields in order" do
    res = Nack::Response.new(200, [["set-cookie", "a=1"], ["set-cookie", "a =2"], ["set-cookie", "a\t=3"], ["set-cookie", "ab=4"], ["set-cookie", "a b=5"], ["b", "a=6"]])
    res.set_cookie("a", "7")
    res.headers.to_a.must_equal [["set-cookie", "ab=4"], ["set-cookie", "a b=5"], ["b", "a=6"], ["set-cookie", "a=7"]]
  end

  it "deletes a cookie with an expiry in the past" do
    res = Nack::Response.new
    res.delete_cookie("a", max_age: 1, path: "b")
    res.headers.to_a.must_equal [["set-cookie", "a=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=b"]]
  end

  it "finishes into a status, fields and the written body" do
    res = Nack::Response.new(201, [["a", "1"]], "b")
    res.write("\xFF".b)
    res.write("é")
    res.finish.must_equal [201, [["a", "1"]], "b\xFF\xC3\xA9".b]
    Nack::Response.new.finish.must_equal [200, [], ""]
  end

  it "drops the body and trailers of a 204, a 205 and a 304 but not of a 101" do
    res = Nack::Response.new(204, [], "a")
    res.trailers.add("b", "1")
    res.finish.must_equal [204, [], ""]
    Nack::Response.new(205, [], "a").finish.must_equal [205, [], ""]
    Nack::Response.new(304, [], "a").finish.must_equal [304, [], ""]
    Nack::Response.new(101, [], "a").finish.must_equal [101, [], "a"]
  end

  it "finishes into a String body when no trailer is added" do
    res = Nack::Response.new(200, [], "a")
    res.trailers
    res.finish.must_equal [200, [], "a"]
  end

  it "carries trailers on a body responding to #each" do
    res = Nack::Response.new(200, [], "a")
    res.trailers.add("b", "1")
    _, _, body = res.finish
    body.to_enum(:each).to_a.must_equal ["a"]
    body.trailers.must_equal [["b", "1"]]
  end
end
