module GitlabCiAuditor
  class ContextLoader
    def initialize(snapshot_file: nil, context_file: nil)
      @snapshot_file = snapshot_file
      @context_file = context_file
    end

    def load(path)
      root_pipeline = PipelineLoader.new(snapshot_file: @snapshot_file).load(path)
      return root_pipeline unless @context_file

      manifest_path = File.expand_path(@context_file)
      raise ArgumentError, "Pipeline context manifest not found: #{manifest_path}" unless File.exist?(manifest_path)

      manifest = JSON.parse(File.read(manifest_path))
      project_map = build_project_map(root_pipeline, manifest, manifest_path, path)
      attach_context_links(project_map, manifest, manifest_path)
      root_pipeline.include_metadata[:context_manifest] = manifest_path
      root_pipeline.include_metadata[:context_projects] = project_map.keys
      root_pipeline
    rescue JSON::ParserError => error
      raise ArgumentError, "Failed to parse context manifest #{@context_file}: #{error.message}"
    end

    private

    def build_project_map(root_pipeline, manifest, manifest_path, root_path)
      root_name = manifest["root_project"].to_s.strip
      root_name = "root" if root_name.empty?

      projects = { root_name => root_pipeline }
      Array(manifest["projects"]).each do |entry|
        next unless entry.is_a?(Hash)

        name = entry["name"].to_s.strip
        next if name.empty?
        next if projects.key?(name)

        project_root = entry["root"].to_s.strip
        next if project_root.empty?

        expanded_root = File.expand_path(project_root, File.dirname(manifest_path))
        if same_pipeline_path?(expanded_root, root_path)
          projects[name] = root_pipeline
          next
        end

        projects[name] = PipelineLoader.new(snapshot_file: @snapshot_file).load(expanded_root)
      end
      projects
    end

    def attach_context_links(project_map, manifest, manifest_path)
      Array(manifest["links"]).each do |entry|
        next unless entry.is_a?(Hash)

        source_name = entry["from_project"].to_s.strip
        target_name = entry["to_project"].to_s.strip
        trigger_job_name = entry["trigger_job_name"].to_s.strip
        next if source_name.empty? || target_name.empty? || trigger_job_name.empty?

        source_pipeline = project_map[source_name]
        target_pipeline = project_map[target_name]
        next unless source_pipeline && target_pipeline

        unless source_pipeline.jobs.key?(trigger_job_name)
          source_pipeline.warnings << "Context link skipped because job #{trigger_job_name.inspect} was not found in project #{source_name}"
          next
        end

        next if source_pipeline.downstream_references.any? { |reference| reference.trigger_job_name == trigger_job_name && reference.pipeline_path == target_pipeline.path }

        source_pipeline.downstream_references << PipelineLoader::DownstreamReference.new(
          trigger_job_name: trigger_job_name,
          kind: (entry["kind"] || "multi_project_context").to_s,
          source: entry.merge("context_manifest" => manifest_path),
          pipeline_path: target_pipeline.path,
          pipeline: target_pipeline
        )
      end
    end

    def same_pipeline_path?(candidate, root_path)
      File.expand_path(candidate) == File.expand_path(root_path)
    end
  end
end
