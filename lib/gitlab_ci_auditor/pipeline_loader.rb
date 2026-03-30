module GitlabCiAuditor
  class PipelineLoader
    Pipeline = Struct.new(
      :path,
      :base_dir,
      :raw_config,
      :jobs,
      :templates,
      :stages,
      :variables,
      :workflow,
      :global_before_script,
      :global_after_script,
      :include_metadata,
      :downstream_references,
      :warnings,
      keyword_init: true
    )

    DownstreamReference = Struct.new(
      :trigger_job_name,
      :kind,
      :source,
      :pipeline_path,
      :pipeline,
      :warning,
      keyword_init: true
    )

    def initialize(snapshot_file: nil)
      @snapshot_file = snapshot_file
      @snapshot_catalog = []
      @snapshot_manifest_path = nil
    end

    def load(path)
      prepare_snapshot_catalog(path)
      load_internal(path, [])
    end

    private

    def load_internal(path, graph_stack)
      absolute_path = File.expand_path(path)
      config, include_metadata, warnings = load_with_includes(absolute_path, [])
      jobs, templates = resolve_jobs(config)

      pipeline = Pipeline.new(
        path: absolute_path,
        base_dir: File.dirname(absolute_path),
        raw_config: config,
        jobs: jobs,
        templates: templates,
        stages: Array(config["stages"]).map(&:to_s),
        variables: config["variables"].is_a?(Hash) ? config["variables"] : {},
        workflow: config["workflow"].is_a?(Hash) ? config["workflow"] : {},
        global_before_script: GitlabCiAuditor.normalize_array(config["before_script"]),
        global_after_script: GitlabCiAuditor.normalize_array(config["after_script"]),
        include_metadata: include_metadata,
        downstream_references: [],
        warnings: warnings
      )

      downstream_references, downstream_warnings = resolve_downstream_references(pipeline, graph_stack + [absolute_path])
      pipeline.downstream_references = downstream_references
      pipeline.warnings.concat(downstream_warnings).uniq!
      pipeline
    end

    def load_with_includes(path, stack)
      raise ArgumentError, "Pipeline file not found: #{path}" unless File.exist?(path)
      raise ArgumentError, "Include cycle detected: #{(stack + [path]).join(' -> ')}" if stack.include?(path)

      parsed = parse_yaml(File.read(path), path)
      unless parsed.is_a?(Hash)
        raise ArgumentError, "Top-level GitLab CI document must be a YAML mapping: #{path}"
      end

      warnings = []
      include_metadata = {
        resolved_local_includes: [],
        template_includes: [],
        unresolved_includes: []
      }

      merged_includes = {}
      normalize_include_entries(parsed["include"]).each do |entry|
        case entry
        when String
          merge_local_include(entry, path, stack, merged_includes, include_metadata, warnings)
        when Hash
          if entry["local"]
            merge_local_include(entry["local"], path, stack, merged_includes, include_metadata, warnings)
          elsif entry["file"] && !entry["project"]
            merge_local_include(entry["file"], path, stack, merged_includes, include_metadata, warnings)
          elsif entry["template"]
            include_metadata[:template_includes] << entry["template"].to_s
          else
            include_metadata[:unresolved_includes] << entry
            warnings << "Skipped non-local include in #{path}: #{entry.inspect}"
          end
        else
          warnings << "Unsupported include entry in #{path}: #{entry.inspect}"
        end
      end

      current = parsed.reject { |key, _| key == "include" }
      merged = GitlabCiAuditor.deep_merge(merged_includes, current)
      [merged, include_metadata, warnings]
    end

    def resolve_downstream_references(pipeline, graph_stack)
      references = []
      warnings = []

      pipeline.jobs.each do |job_name, job|
        references.concat(extract_downstream_references(job_name, job, pipeline, graph_stack, warnings))
      end

      [references, warnings]
    end

    def extract_downstream_references(job_name, job, pipeline, graph_stack, warnings)
      trigger = job["trigger"]
      return [] if trigger.nil?

      case trigger
      when String
        snapshot_reference = build_snapshot_downstream_reference(job_name, { "project" => trigger }, pipeline, graph_stack, warnings, "external_project")
        return snapshot_reference if snapshot_reference

        warning = "Skipped external downstream trigger #{trigger.inspect} in #{pipeline.path} job #{job_name}"
        warnings << warning
        [DownstreamReference.new(
          trigger_job_name: job_name,
          kind: "external_project",
          source: trigger,
          warning: warning
        )]
      when Hash
        if trigger["include"]
          extract_trigger_include_references(job_name, trigger["include"], pipeline, graph_stack, warnings)
        elsif trigger["project"]
          snapshot_reference = build_snapshot_downstream_reference(job_name, trigger, pipeline, graph_stack, warnings, "external_project")
          return snapshot_reference if snapshot_reference

          warning = "Skipped multi-project downstream trigger #{trigger.inspect} in #{pipeline.path} job #{job_name}"
          warnings << warning
          [DownstreamReference.new(
            trigger_job_name: job_name,
            kind: "external_project",
            source: trigger,
            warning: warning
          )]
        else
          []
        end
      else
        warning = "Unsupported downstream trigger in #{pipeline.path} job #{job_name}: #{trigger.inspect}"
        warnings << warning
        [DownstreamReference.new(
          trigger_job_name: job_name,
          kind: "unsupported",
          source: trigger,
          warning: warning
        )]
      end
    end

    def extract_trigger_include_references(job_name, include_value, pipeline, graph_stack, warnings)
      normalize_include_entries(include_value).flat_map do |entry|
        case entry
        when String
          build_local_downstream_reference(job_name, entry, pipeline, graph_stack, warnings, "local_child")
        when Hash
          if entry["local"]
            build_local_downstream_reference(job_name, entry["local"], pipeline, graph_stack, warnings, "local_child", entry)
          elsif entry["file"] && !entry["project"]
            build_local_downstream_reference(job_name, entry["file"], pipeline, graph_stack, warnings, "local_child", entry)
          elsif entry["artifact"]
            snapshot_reference = build_snapshot_downstream_reference(job_name, entry, pipeline, graph_stack, warnings, "artifact_child")
            next snapshot_reference if snapshot_reference

            warning = "Skipped artifact-based downstream trigger #{entry.inspect} in #{pipeline.path} job #{job_name}"
            warnings << warning
            [DownstreamReference.new(
              trigger_job_name: job_name,
              kind: "artifact_child",
              source: entry,
              warning: warning
            )]
          elsif entry["project"]
            snapshot_reference = build_snapshot_downstream_reference(job_name, entry, pipeline, graph_stack, warnings, "external_project")
            next snapshot_reference if snapshot_reference

            warning = "Skipped multi-project child pipeline #{entry.inspect} in #{pipeline.path} job #{job_name}"
            warnings << warning
            [DownstreamReference.new(
              trigger_job_name: job_name,
              kind: "external_project",
              source: entry,
              warning: warning
            )]
          elsif entry["template"]
            warning = "Skipped template-based downstream child #{entry.inspect} in #{pipeline.path} job #{job_name}"
            warnings << warning
            [DownstreamReference.new(
              trigger_job_name: job_name,
              kind: "template_child",
              source: entry,
              warning: warning
            )]
          else
            warning = "Unsupported child pipeline include #{entry.inspect} in #{pipeline.path} job #{job_name}"
            warnings << warning
            [DownstreamReference.new(
              trigger_job_name: job_name,
              kind: "unsupported",
              source: entry,
              warning: warning
            )]
          end
        else
          warning = "Unsupported child pipeline include entry #{entry.inspect} in #{pipeline.path} job #{job_name}"
          warnings << warning
          [DownstreamReference.new(
            trigger_job_name: job_name,
            kind: "unsupported",
            source: entry,
            warning: warning
          )]
        end
      end
    end

    def build_local_downstream_reference(job_name, relative_path, pipeline, graph_stack, warnings, kind, source = nil)
      downstream_path = File.expand_path(relative_path, pipeline.base_dir)
      if graph_stack.include?(downstream_path)
        warning = "Detected downstream pipeline cycle #{(graph_stack + [downstream_path]).join(' -> ')}"
        warnings << warning
        return [DownstreamReference.new(
          trigger_job_name: job_name,
          kind: "cycle",
          source: source || { "local" => relative_path },
          pipeline_path: downstream_path,
          warning: warning
        )]
      end

      unless File.exist?(downstream_path)
        warning = "Missing downstream pipeline #{relative_path} referenced from #{pipeline.path} job #{job_name}"
        warnings << warning
        return [DownstreamReference.new(
          trigger_job_name: job_name,
          kind: "missing",
          source: source || { "local" => relative_path },
          pipeline_path: downstream_path,
          warning: warning
        )]
      end

      child_pipeline = load_internal(downstream_path, graph_stack)
      [DownstreamReference.new(
        trigger_job_name: job_name,
        kind: kind,
        source: source || { "local" => relative_path },
        pipeline_path: downstream_path,
        pipeline: child_pipeline
      )]
    end

    def prepare_snapshot_catalog(root_path)
      manifest_path =
        if @snapshot_file
          File.expand_path(@snapshot_file)
        else
          detect_snapshot_manifest(root_path)
        end

      if @snapshot_file && !File.exist?(manifest_path)
        raise ArgumentError, "Snapshot manifest not found: #{manifest_path}"
      end

      if manifest_path && File.exist?(manifest_path)
        parsed = JSON.parse(File.read(manifest_path))
        @snapshot_catalog = Array(parsed["snapshots"])
        @snapshot_manifest_path = manifest_path
      else
        @snapshot_catalog = []
        @snapshot_manifest_path = nil
      end
    rescue JSON::ParserError => error
      raise ArgumentError, "Failed to parse snapshot manifest #{manifest_path}: #{error.message}"
    end

    def detect_snapshot_manifest(root_path)
      base_dir = File.dirname(File.expand_path(root_path))
      candidates = [
        File.join(base_dir, ".gitlab-ci-downstream-snapshots.json"),
        File.join(base_dir, "downstream_snapshots.json")
      ]
      candidates.find { |candidate| File.exist?(candidate) }
    end

    def build_snapshot_downstream_reference(job_name, trigger_source, pipeline, graph_stack, warnings, kind)
      snapshot_entry = find_snapshot_entry(kind, job_name, trigger_source)
      return nil unless snapshot_entry

      snapshot_value = snapshot_entry["snapshot"].to_s
      if snapshot_value.strip.empty?
        warning = "Snapshot entry for #{kind} in job #{job_name} does not declare a snapshot path"
        warnings << warning
        return [DownstreamReference.new(
          trigger_job_name: job_name,
          kind: "#{kind}_snapshot_missing",
          source: trigger_source,
          warning: warning
        )]
      end

      snapshot_path = File.expand_path(snapshot_value, File.dirname(@snapshot_manifest_path || pipeline.base_dir))
      if graph_stack.include?(snapshot_path)
        warning = "Detected downstream pipeline cycle #{(graph_stack + [snapshot_path]).join(' -> ')}"
        warnings << warning
        return [DownstreamReference.new(
          trigger_job_name: job_name,
          kind: "#{kind}_snapshot_cycle",
          source: trigger_source,
          pipeline_path: snapshot_path,
          warning: warning
        )]
      end

      unless File.exist?(snapshot_path)
        warning = "Snapshot file #{snapshot_value} referenced for #{kind} in job #{job_name} does not exist"
        warnings << warning
        return [DownstreamReference.new(
          trigger_job_name: job_name,
          kind: "#{kind}_snapshot_missing",
          source: trigger_source,
          pipeline_path: snapshot_path,
          warning: warning
        )]
      end

      snapshot_pipeline = load_internal(snapshot_path, graph_stack)
      [DownstreamReference.new(
        trigger_job_name: job_name,
        kind: "#{kind}_snapshot",
        source: trigger_source,
        pipeline_path: snapshot_path,
        pipeline: snapshot_pipeline
      )]
    end

    def find_snapshot_entry(kind, job_name, trigger_source)
      @snapshot_catalog.find do |entry|
        snapshot_kind_match?(entry, kind) &&
          snapshot_job_match?(entry, job_name) &&
          snapshot_trigger_match?(entry, kind, trigger_source)
      end
    end

    def snapshot_kind_match?(entry, kind)
      aliases = {
        "external_project" => %w[external_project project],
        "artifact_child" => %w[artifact_child artifact]
      }
      Array(aliases.fetch(kind, [kind])).include?(entry["kind"].to_s)
    end

    def snapshot_job_match?(entry, job_name)
      expected = entry["trigger_job_name"].to_s
      expected.empty? || expected == job_name
    end

    def snapshot_trigger_match?(entry, kind, trigger_source)
      case kind
      when "external_project"
        project_matches = entry["project"].to_s.empty? || entry["project"].to_s == trigger_source["project"].to_s
        file_value = trigger_source["file"] || trigger_source["local"]
        file_matches = entry["file"].to_s.empty? || entry["file"].to_s == file_value.to_s
        ref_value = trigger_source["branch"] || trigger_source["ref"]
        ref_matches = entry["ref"].to_s.empty? || entry["ref"].to_s == ref_value.to_s
        project_matches && file_matches && ref_matches
      when "artifact_child"
        artifact_matches = entry["artifact"].to_s.empty? || entry["artifact"].to_s == trigger_source["artifact"].to_s
        job_matches = entry["job"].to_s.empty? || entry["job"].to_s == trigger_source["job"].to_s
        artifact_matches && job_matches
      else
        false
      end
    end

    def merge_local_include(relative_path, current_path, stack, merged_includes, include_metadata, warnings)
      include_path = File.expand_path(relative_path, File.dirname(current_path))
      unless File.exist?(include_path)
        include_metadata[:unresolved_includes] << { "local" => relative_path }
        warnings << "Missing local include #{relative_path} referenced from #{current_path}"
        return
      end

      included_config, nested_metadata, nested_warnings = load_with_includes(include_path, stack + [current_path])
      merged_includes.replace(GitlabCiAuditor.deep_merge(merged_includes, included_config))
      include_metadata[:resolved_local_includes] << include_path
      include_metadata[:resolved_local_includes].concat(nested_metadata[:resolved_local_includes])
      include_metadata[:template_includes].concat(nested_metadata[:template_includes])
      include_metadata[:unresolved_includes].concat(nested_metadata[:unresolved_includes])
      warnings.concat(nested_warnings)
    end

    def normalize_include_entries(entries)
      case entries
      when nil
        []
      when Array
        entries
      else
        [entries]
      end
    end

    def parse_yaml(content, path)
      sanitized = content.gsub(/!reference\s+\[[^\]\n]+\]/, '"__gitlab_reference__"')
      YAML.safe_load(sanitized, aliases: true) || {}
    rescue Psych::BadAlias => error
      alias_name = error.message.to_s[/Unknown alias:\s+(.+)$/, 1] || "unknown"
      raise ArgumentError, "Failed to parse #{path}: Unknown YAML alias `#{alias_name}`. YAML anchors and aliases must be defined in the same file. If this alias comes from an included file, replace it with `!reference`, `extends`, or move the anchor definition into the selected root file."
    rescue Psych::Exception => error
      raise ArgumentError, "Failed to parse #{path}: #{error.message}"
    end

    def resolve_jobs(config)
      job_definitions = config.each_with_object({}) do |(name, value), jobs|
        jobs[name] = value if GitlabCiAuditor.job_definition?(name, value)
      end

      resolved = {}
      resolving = []
      job_definitions.each_key do |name|
        resolved[name] = resolve_single_job(name, job_definitions, config["default"], resolved, resolving)
      end

      visible = resolved.reject { |name, _| name.start_with?(".") }
      templates = resolved.select { |name, _| name.start_with?(".") }
      [visible, templates]
    end

    def resolve_single_job(name, definitions, default_config, cache, resolving)
      return cache[name] if cache.key?(name)
      raise ArgumentError, "Cyclic extends detected for job #{name}" if resolving.include?(name)

      resolving << name
      job = GitlabCiAuditor.deep_copy(definitions.fetch(name))
      parent_names = Array(job.delete("extends"))

      resolved = GitlabCiAuditor.deep_copy(default_config.is_a?(Hash) ? default_config : {})
      parent_names.each do |parent_name|
        unless definitions.key?(parent_name)
          resolving.pop
          raise ArgumentError, "Job #{name} extends unknown template #{parent_name}"
        end

        parent_job = resolve_single_job(parent_name, definitions, default_config, cache, resolving)
        resolved = GitlabCiAuditor.deep_merge(resolved, parent_job)
      end

      resolved = GitlabCiAuditor.deep_merge(resolved, job)
      resolved["__name"] = name
      cache[name] = resolved
      resolving.pop
      resolved
    end
  end
end
