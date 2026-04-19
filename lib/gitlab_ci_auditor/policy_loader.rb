module GitlabCiAuditor
  class PolicyLoader
    DEFAULT_PACK = "balanced".freeze
    TOP_LEVEL_KEYS = %w[
      meta
      production_environments
      required_controls
      security_policies
      severity_tuning
      stack_sast_requirements
      test_environments
    ].freeze
    META_KEYS = %w[name label description source].freeze
    REQUIRED_CONTROL_KEYS = %w[unit_tests coverage_report sast scan sbom secret_detection iac dast deploy_test].freeze
    SECURITY_POLICY_KEYS = %w[
      forbid_latest_images
      forbid_unpinned_images
      forbid_allow_failure_on_security
      forbid_manual_test_deploy
      forbid_strict_host_key_bypass
      forbid_inline_secrets
      forbid_remote_script_piping
    ].freeze
    SEVERITY_TUNING_SECTIONS = %w[all security ssdlc].freeze
    SEVERITY_TUNING_KEYS = %w[exact exact_titles contains title_contains].freeze
    STACK_REQUIREMENT_KEYS = %w[label accepted_families].freeze
    SEVERITY_VALUES = %w[critical high blocker warning warn medium moderate low info minor].freeze

    class << self
      def load(path: nil, pack: nil)
        return load_file(path) if path

        load_pack(pack || DEFAULT_PACK)
      end

      def load_json(json, source: "inline policy", name: "gui_policy", label: "GUI Policy", policy_source: "gui_policy", force_meta: false)
        policy = JSON.parse(json.to_s)
        load_data(
          policy,
          source: source,
          meta_defaults: {
            "name" => name.to_s.strip.empty? ? "gui_policy" : name.to_s.strip,
            "label" => label.to_s.strip.empty? ? "GUI Policy" : label.to_s.strip,
            "source" => policy_source
          },
          force_meta: force_meta
        )
      rescue JSON::ParserError => e
        raise ArgumentError, "Invalid policy JSON in #{source}: #{e.message}"
      end

      def load_file(path)
        absolute_path = File.expand_path(path)
        load_data(
          parse_policy_json(absolute_path),
          source: absolute_path,
          meta_defaults: {
            "name" => File.basename(absolute_path, File.extname(absolute_path)),
            "label" => "Custom Policy File",
            "source" => "file"
          },
          force_meta: false
        )
      end

      def load_pack(name)
        pack_path = pack_path_for(name)
        raise ArgumentError, "Unknown policy pack: #{name}" unless pack_path && File.exist?(pack_path)

        load_data(
          parse_policy_json(pack_path),
          source: pack_path,
          meta_defaults: {
            "name" => name,
            "label" => name,
            "source" => "policy_pack"
          },
          force_meta: false
        )
      end

      def available_packs
        Dir.glob(File.join(policy_pack_dir, "*.json")).sort.map do |path|
          policy = parse_policy_json(path)
          validate_policy!(policy, source: path)
          meta = policy["meta"].is_a?(Hash) ? policy["meta"] : {}
          {
            name: File.basename(path, ".json"),
            label: meta["label"] || File.basename(path, ".json"),
            description: meta["description"].to_s
          }
        end
      end

      def catalog_entries
        available_packs.map do |pack|
          policy = load_pack(pack[:name])
          {
            id: "pack:#{pack[:name]}",
            kind: "pack",
            name: policy.dig("meta", "name"),
            label: policy.dig("meta", "label"),
            description: policy.dig("meta", "description").to_s,
            source: policy.dig("meta", "source"),
            json: JSON.pretty_generate(policy)
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

      def parse_policy_json(path)
        JSON.parse(File.read(path))
      rescue JSON::ParserError => e
        raise ArgumentError, "Invalid policy JSON in #{path}: #{e.message}"
      end

      def pack_path_for(name)
        File.join(policy_pack_dir, "#{name}.json")
      end

      def validate_policy!(policy, source:)
        raise ArgumentError, "Policy #{source} must contain a JSON object at the top level" unless policy.is_a?(Hash)

        validate_supported_keys!(policy.keys, TOP_LEVEL_KEYS, "policy", source)
        validate_meta!(policy["meta"], source)
        validate_boolean_hash!(policy["required_controls"], REQUIRED_CONTROL_KEYS, "required_controls", source)
        validate_string_array!(policy["test_environments"], "test_environments", source)
        validate_string_array!(policy["production_environments"], "production_environments", source)
        validate_boolean_hash!(policy["security_policies"], SECURITY_POLICY_KEYS, "security_policies", source)
        validate_severity_tuning!(policy["severity_tuning"], source)
        validate_stack_sast_requirements!(policy["stack_sast_requirements"], source)
      end

      def validate_meta!(meta, source)
        return if meta.nil?
        raise ArgumentError, "Policy #{source} key `meta` must be an object" unless meta.is_a?(Hash)

        validate_supported_keys!(meta.keys, META_KEYS, "meta", source)
        %w[name label description source].each do |key|
          next unless meta.key?(key)
          next if meta[key].is_a?(String)

          raise ArgumentError, "Policy #{source} meta key `#{key}` must be a string"
        end
      end

      def validate_boolean_hash!(value, allowed_keys, section, source)
        return if value.nil?
        raise ArgumentError, "Policy #{source} key `#{section}` must be an object" unless value.is_a?(Hash)

        validate_supported_keys!(value.keys, allowed_keys, section, source)
        value.each do |key, item|
          next if item == true || item == false

          raise ArgumentError, "Policy #{source} key `#{section}.#{key}` must be a boolean"
        end
      end

      def validate_string_array!(value, section, source)
        return if value.nil?
        raise ArgumentError, "Policy #{source} key `#{section}` must be an array of strings" unless value.is_a?(Array)

        value.each do |item|
          next if item.is_a?(String)

          raise ArgumentError, "Policy #{source} key `#{section}` must contain only strings"
        end
      end

      def validate_severity_tuning!(value, source)
        return if value.nil?
        raise ArgumentError, "Policy #{source} key `severity_tuning` must be an object" unless value.is_a?(Hash)

        validate_supported_keys!(value.keys, SEVERITY_TUNING_SECTIONS, "severity_tuning", source)
        value.each do |section, rules|
          raise ArgumentError, "Policy #{source} key `severity_tuning.#{section}` must be an object" unless rules.is_a?(Hash)

          validate_supported_keys!(rules.keys, SEVERITY_TUNING_KEYS, "severity_tuning.#{section}", source)
          rules.each do |rule_key, mappings|
            raise ArgumentError, "Policy #{source} key `severity_tuning.#{section}.#{rule_key}` must be an object" unless mappings.is_a?(Hash)

            mappings.each do |title_match, severity|
              raise ArgumentError, "Policy #{source} key `severity_tuning.#{section}.#{rule_key}` requires string match keys" unless title_match.is_a?(String)
              next if SEVERITY_VALUES.include?(severity.to_s.strip.downcase)

              raise ArgumentError, "Policy #{source} key `severity_tuning.#{section}.#{rule_key}.#{title_match}` has unsupported severity `#{severity}`"
            end
          end
        end
      end

      def validate_stack_sast_requirements!(value, source)
        return if value.nil?
        raise ArgumentError, "Policy #{source} key `stack_sast_requirements` must be an object" unless value.is_a?(Hash)

        value.each do |stack_key, config|
          raise ArgumentError, "Policy #{source} key `stack_sast_requirements.#{stack_key}` must be an object" unless config.is_a?(Hash)

          validate_supported_keys!(config.keys, STACK_REQUIREMENT_KEYS, "stack_sast_requirements.#{stack_key}", source)
          if config.key?("label") && !config["label"].is_a?(String)
            raise ArgumentError, "Policy #{source} key `stack_sast_requirements.#{stack_key}.label` must be a string"
          end

          next unless config.key?("accepted_families")

          families = config["accepted_families"]
          raise ArgumentError, "Policy #{source} key `stack_sast_requirements.#{stack_key}.accepted_families` must be an array of strings" unless families.is_a?(Array)

          families.each do |family|
            next if family.is_a?(String)

            raise ArgumentError, "Policy #{source} key `stack_sast_requirements.#{stack_key}.accepted_families` must contain only strings"
          end
        end
      end

      def validate_supported_keys!(keys, allowed_keys, section, source)
        unsupported = Array(keys).map(&:to_s) - allowed_keys
        return if unsupported.empty?

        raise ArgumentError, "Policy #{source} has unsupported #{section} key(s): #{unsupported.sort.join(', ')}"
      end

      def apply_meta(policy, defaults)
        policy["meta"] = defaults.merge(policy["meta"].is_a?(Hash) ? policy["meta"] : {})
        policy
      end

      def load_data(policy, source:, meta_defaults:, force_meta:)
        validate_policy!(policy, source: source)
        if force_meta
          policy["meta"] = (policy["meta"].is_a?(Hash) ? policy["meta"] : {}).merge(meta_defaults)
          policy
        else
          apply_meta(policy, meta_defaults.merge("label" => policy.dig("meta", "label") || meta_defaults["label"]))
        end
      end
    end
  end
end
