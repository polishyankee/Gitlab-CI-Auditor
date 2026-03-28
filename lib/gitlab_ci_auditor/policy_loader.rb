module GitlabCiAuditor
  class PolicyLoader
    DEFAULT_PACK = "balanced".freeze

    class << self
      def load(path: nil, pack: nil)
        return load_file(path) if path

        load_pack(pack || DEFAULT_PACK)
      end

      def load_file(path)
        absolute_path = File.expand_path(path)
        policy = JSON.parse(File.read(absolute_path))
        apply_meta(policy, {
          "name" => File.basename(absolute_path, File.extname(absolute_path)),
          "label" => policy.dig("meta", "label") || "Custom Policy File",
          "source" => "file"
        })
      end

      def load_pack(name)
        pack_path = pack_path_for(name)
        raise ArgumentError, "Unknown policy pack: #{name}" unless pack_path && File.exist?(pack_path)

        policy = JSON.parse(File.read(pack_path))
        apply_meta(policy, {
          "name" => name,
          "label" => policy.dig("meta", "label") || name,
          "source" => "policy_pack"
        })
      end

      def available_packs
        Dir.glob(File.join(policy_pack_dir, "*.json")).sort.map do |path|
          policy = JSON.parse(File.read(path))
          meta = policy["meta"].is_a?(Hash) ? policy["meta"] : {}
          {
            name: File.basename(path, ".json"),
            label: meta["label"] || File.basename(path, ".json"),
            description: meta["description"].to_s
          }
        end
      end

      def pack_names
        available_packs.map { |pack| pack[:name] }
      end

      def policy_pack_dir
        File.join(GitlabCiAuditor.root_dir, "config", "policies")
      end

      private

      def pack_path_for(name)
        File.join(policy_pack_dir, "#{name}.json")
      end

      def apply_meta(policy, defaults)
        policy["meta"] = defaults.merge(policy["meta"].is_a?(Hash) ? policy["meta"] : {})
        policy
      end
    end
  end
end
