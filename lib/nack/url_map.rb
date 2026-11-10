# frozen_string_literal: true

module Nack
  class URLMap
    Mount = Data.define(:host, :prefix, :subtree, :app)
    private_constant :Mount

    def initialize(mapping)
      @mounts = mapping.map { |reference, app| mount(reference, app) }
        .sort_by { [it.host ? 0 : 1, -it.prefix.bytesize] }.freeze
    end

    def call(request)
      script_name = request.script_name
      path_info = request.path_info
      if script_name.start_with?("/") || path_info.start_with?("/")
        mount = @mounts.find do
          (path_info.start_with?(it.subtree) || path_info == it.prefix) && (it.host.nil? || it.host.casecmp(request.host) == 0)
        end
      end
      return [404, [["content-type", "text/plain"]], "Not Found"] unless mount
      prefix = mount.prefix
      request.script_name = script_name.empty? ? prefix : script_name + prefix
      request.path_info = path_info.byteslice(prefix.bytesize, path_info.bytesize)
      mount.app.call(request)
    ensure
      request.script_name = script_name
      request.path_info = path_info
    end

    private

    def mount(reference, app)
      host, path = split_reference(reference)
      prefix = path.chomp("/").b.freeze
      Mount.new(host, prefix, (prefix + "/").freeze, app)
    end

    def split_reference(reference)
      unless reference.start_with?("//")
        raise ArgumentError, "reference must start with /: #{reference.inspect}" unless reference.start_with?("/")
        return [nil, reference]
      end
      host, path = reference.delete_prefix("//").split("/", 2)
      match = Request::AUTHORITY.match(host)
      raise ArgumentError, "reference must name a host and no port: #{reference.inspect}" unless match && match[1] == host
      [host.b.freeze, "/#{path}"]
    end
  end
end
