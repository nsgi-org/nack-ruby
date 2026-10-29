# frozen_string_literal: true

module Nack
  module MIME
    TYPES = {
      "avif" => "image/avif",
      "css" => "text/css",
      "eot" => "application/vnd.ms-fontobject",
      "htm" => "text/html",
      "html" => "text/html",
      "ico" => "image/vnd.microsoft.icon",
      "jpeg" => "image/jpeg",
      "jpg" => "image/jpeg",
      "js" => "text/javascript",
      "json" => "application/json",
      "mjs" => "text/javascript",
      "mp1" => "audio/mpeg",
      "mp2" => "audio/mpeg",
      "mp3" => "audio/mpeg",
      "oga" => "audio/ogg",
      "ogg" => "audio/ogg",
      "ogv" => "video/ogg",
      "opus" => "audio/ogg",
      "pdf" => "application/pdf",
      "png" => "image/png",
      "spx" => "audio/ogg",
      "svg" => "image/svg+xml",
      "ttc" => "font/collection",
      "vtt" => "text/vtt",
      "wasm" => "application/wasm",
      "webmanifest" => "application/manifest+json",
      "webp" => "image/webp",
      "woff" => "font/woff",
      "woff2" => "font/woff2",
      "xml" => "application/xml"
    }.then { |types| Ractor.make_shareable(types.merge(types.transform_keys { ".#{it}" })) }

    module_function

    def [](ext)
      TYPES[ext] || TYPES[ext.downcase]
    end
  end
end
