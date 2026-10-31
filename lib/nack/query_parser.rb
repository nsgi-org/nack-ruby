# frozen_string_literal: true

module Nack
  class QueryParser
    def initialize(param_limit: 4096, depth_limit: 32)
      @param_limit = param_limit
      @depth_limit = depth_limit
      freeze
    end

    def parse_query(string)
      params = []
      each_param(string) { |name, value| params << [name, value] }
      params
    end

    def parse_nested_query(string)
      params = {}
      each_param(string) do |name, value|
        keys = split_name(name)
        raise ParamError, "too deeply nested: #{name.inspect}" if keys.size > @depth_limit
        store(params, keys, value, name)
      end
      params
    end

    def build_query(params)
      params.map { |name, value| build_param(Utils.escape(name), value) }.join("&")
    end

    def build_nested_query(params)
      join(params.map { |name, value| build_nested_param(Utils.escape(name), value) })
    end

    private

    def each_param(string)
      pairs = string.b.split("&", @param_limit + 1)
      raise ParamError, "too many parameters" if pairs.size > @param_limit
      pairs.each do |pair|
        next if pair.empty?
        name, value = pair.split("=", 2)
        yield Utils.unescape(name), value ? Utils.unescape(value) : +""
      end
    end

    def split_name(name)
      start = name.index("[")
      return [name] unless start && /\A[^\[\]]+(?:\[[^\[\]]*\])*\z/.match?(name)
      inner = name[start + 1...-1]
      inner.empty? ? [name[0, start], ""] : [name[0, start], *inner.split("][", -1)]
    end

    def store(container, keys, value, name)
      key, *rest = keys
      if rest.empty?
        return container << value if container.is_a?(Array)
        raise ParamError, "conflicting shapes: #{name.inspect}" if container[key] in Array | Hash
        return container[key] = value
      end
      type = rest.first.empty? ? Array : Hash
      if container.is_a?(Array)
        container << type.new unless container.last.instance_of?(type) && !occupied?(container.last, rest)
        child = container.last
      else
        child = container.fetch(key) { container[key] = type.new }
        raise ParamError, "conflicting shapes: #{name.inspect}" unless child.instance_of?(type)
      end
      store(child, rest, value, name)
    end

    def occupied?(container, keys)
      case container
      when Array then false
      when Hash
        key, *rest = keys
        container.key?(key) && (rest.empty? || occupied?(container[key], rest))
      else true
      end
    end

    def build_param(escaped_name, value)
      "#{escaped_name}=#{Utils.escape(value)}"
    end

    def build_nested_param(escaped_name, value)
      case value
      when Array then join(value.map { build_nested_param("#{escaped_name}%5B%5D", it) })
      when Hash then join(value.map { |key, child| build_nested_param("#{escaped_name}%5B#{Utils.escape(key)}%5D", child) })
      else build_param(escaped_name, value)
      end
    end

    def join(parts)
      parts.reject(&:empty?).join("&")
    end
  end
end
