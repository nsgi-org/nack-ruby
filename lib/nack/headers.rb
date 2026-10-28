# frozen_string_literal: true

module Nack
  class Headers
    def initialize(fields = [].freeze)
      @fields = fields.map { |field| field.frozen? ? field : field.dup.freeze }
    end

    def [](name)
      @fields.assoc(name)&.last
    end

    def get_all(name)
      @fields.filter_map { |key, value| value if key == name }
    end

    def []=(name, value)
      field = validated_field(name, value)
      index = @fields.index { |key, _| key == name }
      unless index
        @fields << field
        return
      end
      @fields[index] = field
      i = index + 1
      while i < @fields.size
        if @fields[i][0] == name
          @fields.delete_at(i)
        else
          i += 1
        end
      end
    end

    def add(name, value)
      @fields << validated_field(name, value)
      self
    end

    def delete(name)
      @fields.reject! { |key, _| key == name }
      self
    end

    def to_a
      @fields.dup
    end

    private

    def validated_field(name, value)
      raise SpecError, "invalid header name: #{name.inspect}" unless Spec.valid_header_name?(name)
      raise SpecError, "invalid header value: #{value.inspect}" unless Spec.valid_header_value?(value)
      [name, value].freeze
    end
  end
end
