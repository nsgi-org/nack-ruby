# frozen_string_literal: true

module Nack
  module Utils
    module_function

    def no_entity_body?(status)
      (100..199).cover?(status) || status == 204 || status == 304
    end

    def get_header(pairs, name)
      pairs.assoc(name)&.last
    end

    def set_header(pairs, name, value)
      pairs.reject! { |key, _| key == name }
      pairs << [name, value]
      pairs
    end

    def delete_header(pairs, name)
      pairs.reject! { |key, _| key == name }
      pairs
    end

    def body_size(body)
      case body
      when nil then 0
      when IO::Buffer then body.size
      else body.to_s.bytesize
      end
    end
  end
end
