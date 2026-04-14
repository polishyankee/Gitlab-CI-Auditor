module GitlabCiAuditor
  class CLI
    def self.start(argv)
      new.start(argv)
    end

    def start(argv)
      command = argv.shift
      case command
      when "scan"
        scan(argv)
      when "flatten"
        flatten(argv)
      when "serve"
        serve(argv)
      when "list-packs"
        list_packs
      else
        puts usage
        exit(command.nil? ? 0 : 1)
      end
    end

    private

    def scan(argv)
      options = {
        format: "text",
        output: nil,
        policy: nil,
        policy_pack: PolicyLoader::DEFAULT_PACK,
        snapshot_file: nil,
        context_file: nil,
        history_file: nil,
        compare_to: nil,
        compare_snapshot_file: nil,
        compare_context_file: nil
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: gitlab-ci-auditor scan PATH [--format text|json|json-bundle|html|csv|pdf|sarif|junit] [--output FILE] [--policy FILE] [--policy-pack NAME] [--snapshot-file FILE] [--context-file FILE] [--history-file FILE] [--compare-to PATH]"
        opts.on("--format FORMAT", "text, json, json-bundle, html, csv, pdf, sarif, junit") { |value| options[:format] = value }
        opts.on("--output FILE", "Write report to file") { |value| options[:output] = value }
        opts.on("--policy FILE", "Load custom policy JSON") { |value| options[:policy] = value }
        opts.on("--policy-pack NAME", "Use a bundled policy pack (default: #{PolicyLoader::DEFAULT_PACK})") { |value| options[:policy_pack] = value }
        opts.on("--snapshot-file FILE", "Load downstream snapshot mappings from JSON") { |value| options[:snapshot_file] = value }
        opts.on("--context-file FILE", "Load a multi-project context manifest from JSON") { |value| options[:context_file] = value }
        opts.on("--history-file FILE", "Append this scan to a history store JSON file and include trend data") { |value| options[:history_file] = value }
        opts.on("--compare-to PATH", "Compare the current pipeline revision against another pipeline path") { |value| options[:compare_to] = value }
        opts.on("--compare-snapshot-file FILE", "Downstream snapshot manifest for the comparison pipeline") { |value| options[:compare_snapshot_file] = value }
        opts.on("--compare-context-file FILE", "Multi-project context manifest for the comparison pipeline") { |value| options[:compare_context_file] = value }
      end
      parser.parse!(argv)

      path = argv.shift
      raise ArgumentError, "Pipeline path is required" unless path
      raise ArgumentError, "PDF output requires --output FILE" if options[:format] == "pdf" && options[:output].nil?

      policy = load_policy(options)
      pipeline = load_pipeline_with_diagnostics(path, options[:snapshot_file], options[:context_file])
      report = Analyzer.new(pipeline, policy).analyze
      if options[:compare_to]
        baseline_pipeline = load_pipeline_with_diagnostics(
          options[:compare_to],
          options[:compare_snapshot_file] || options[:snapshot_file],
          options[:compare_context_file] || options[:context_file]
        )
        baseline_report = Analyzer.new(baseline_pipeline, policy).analyze
        report[:diff] = ReportDiff.build(report, baseline_report)
      end
      report = HistoryStore.new(options[:history_file]).attach(report) if options[:history_file]
      renderer = ReportRenderer.new(report)
      output =
        case options[:format]
        when "json"
          JSON.pretty_generate(report)
        when "json-bundle", "json_bundle", "bundle"
          renderer.render_json_bundle
        when "html"
          renderer.render_html
        when "csv"
          renderer.render_csv
        when "pdf"
          renderer.render_pdf
        when "sarif"
          renderer.render_sarif
        when "junit", "junit-xml", "xml"
          renderer.render_junit
        else
          renderer.render_text
        end

      if options[:output]
        File.write(File.expand_path(options[:output]), output)
        puts "Report written to #{File.expand_path(options[:output])}"
      else
        puts output
      end
    end

    def flatten(argv)
      options = {
        output: nil,
        snapshot_file: nil
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: gitlab-ci-auditor flatten PATH [--snapshot-file FILE] [--output FILE]"
        opts.on("--snapshot-file FILE", "Load downstream snapshot mappings from JSON before flattening includes") { |value| options[:snapshot_file] = value }
        opts.on("--output FILE", "Write flattened YAML to file") { |value| options[:output] = value }
      end
      parser.parse!(argv)

      path = argv.shift
      raise ArgumentError, "Pipeline path is required" unless path

      flattened = flatten_pipeline_with_diagnostics(path, options[:snapshot_file])
      output = flattened.yaml

      if options[:output]
        File.write(File.expand_path(options[:output]), output)
        puts "Flattened pipeline written to #{File.expand_path(options[:output])}"
      else
        puts output
      end
    end

    def serve(argv)
      options = {
        host: "127.0.0.1",
        port: 4567,
        policy: nil,
        policy_pack: PolicyLoader::DEFAULT_PACK,
        snapshot_file: nil,
        context_file: nil,
        history_file: nil
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: gitlab-ci-auditor serve [--host HOST] [--port PORT] [--policy FILE] [--policy-pack NAME] [--snapshot-file FILE] [--context-file FILE] [--history-file FILE]"
        opts.on("--host HOST", "Bind host") { |value| options[:host] = value }
        opts.on("--port PORT", Integer, "Bind port") { |value| options[:port] = value }
        opts.on("--policy FILE", "Load custom policy JSON") { |value| options[:policy] = value }
        opts.on("--policy-pack NAME", "Default bundled policy pack (default: #{PolicyLoader::DEFAULT_PACK})") { |value| options[:policy_pack] = value }
        opts.on("--snapshot-file FILE", "Default downstream snapshot manifest for GUI analysis") { |value| options[:snapshot_file] = value }
        opts.on("--context-file FILE", "Default multi-project context manifest for GUI analysis") { |value| options[:context_file] = value }
        opts.on("--history-file FILE", "Default history store JSON file for GUI trend views") { |value| options[:history_file] = value }
      end
      parser.parse!(argv)

      GitlabCiAuditor.require_server!

      puts "Serving GitLab CI auditor on http://#{options[:host]}:#{options[:port]}"
      Server.new(
        host: options[:host],
        port: options[:port],
        policy_path: options[:policy],
        policy_pack: options[:policy_pack],
        snapshot_file: options[:snapshot_file],
        context_file: options[:context_file],
        history_file: options[:history_file]
      ).start
    end

    def list_packs
      puts "Available policy packs:"
      PolicyLoader.available_packs.each do |pack|
        suffix = pack[:description].empty? ? "" : " - #{pack[:description]}"
        puts "  - #{pack[:name]} (#{pack[:label]})#{suffix}"
      end
    end

    def load_policy(options)
      PolicyLoader.load(path: options[:policy], pack: options[:policy_pack])
    end

    def flatten_pipeline_with_diagnostics(path, snapshot_file)
      PipelineLoader.new(snapshot_file: snapshot_file).flatten(path)
    rescue ArgumentError => e
      raise enrich_scan_error(e, path)
    end

    def load_pipeline_with_diagnostics(path, snapshot_file, context_file)
      ContextLoader.new(snapshot_file: snapshot_file, context_file: context_file).load(path)
    rescue ArgumentError => e
      raise enrich_scan_error(e, path)
    end

    def enrich_scan_error(error, path)
      message = error.message.to_s
      workspace = File.dirname(File.expand_path(path))
      diagnostics = build_scan_diagnostics(workspace, path)
      guidance = "If this pipeline depends on `include:project`, place every referenced YAML snapshot in the same bundle directory as the root file, or preserve the original nested repository paths inside that bundle."

      if message.include?("Unknown YAML alias `")
        return ArgumentError.new(([message] + scan_diagnostic_lines(diagnostics) + [guidance]).join("\n"))
      end

      if message.include?("extends unknown template")
        missing_template = message[/extends unknown template\s+(.+)$/, 1]
        template_files = missing_template ? diagnostics[:template_locations][missing_template].to_a : []
        template_hint =
          if template_files.any?
            "Template `#{missing_template}` was found in workspace file(s): #{template_files.join(', ')}. This usually means the template exists locally but is not part of the resolved include graph."
          elsif diagnostics[:template_locations].any?
            "Hidden templates detected in workspace: #{diagnostics[:template_locations].keys.sort.first(20).join(', ')}"
          end

        return ArgumentError.new(([message, template_hint] + scan_diagnostic_lines(diagnostics) + [guidance]).compact.join("\n"))
      end

      if message.include?("Pipeline file not found")
        return ArgumentError.new(([message] + scan_diagnostic_lines(diagnostics) + [guidance]).join("\n"))
      end

      error
    end

    def build_scan_diagnostics(workspace, selected_path)
      yaml_files = Dir.glob(File.join(workspace, "**", "*"), File::FNM_DOTMATCH).select do |candidate|
        File.file?(candidate) && %w[.yml .yaml].include?(File.extname(candidate))
      end

      template_locations = Hash.new { |hash, key| hash[key] = [] }
      alias_definitions = []
      alias_references = []

      yaml_files.each do |yaml_file|
        relative_path = relative_to_workspace(workspace, yaml_file)
        extract_template_definitions(File.read(yaml_file)).each do |template_name|
          template_locations[template_name] << relative_path
        end
        alias_definitions.concat(extract_anchor_definitions(File.read(yaml_file)))
        alias_references.concat(extract_anchor_references(File.read(yaml_file)))
      end

      {
        selected_root: relative_to_workspace(workspace, File.expand_path(selected_path)),
        workspace_files: yaml_files.map { |yaml_file| relative_to_workspace(workspace, yaml_file) }.sort.first(20),
        template_locations: template_locations.transform_values { |paths| paths.uniq.sort.first(6) },
        alias_definitions: alias_definitions.uniq.sort.first(20),
        alias_references: alias_references.uniq.sort.first(20)
      }
    end

    def scan_diagnostic_lines(diagnostics)
      return [] unless diagnostics

      lines = []
      lines << "Selected root pipeline: #{diagnostics[:selected_root]}" if diagnostics[:selected_root]
      lines << "YAML files detected in workspace: #{diagnostics[:workspace_files].join(', ')}" if diagnostics[:workspace_files].any?
      template_names = diagnostics[:template_locations].keys.sort.first(20)
      lines << "Hidden templates detected in workspace: #{template_names.join(', ')}" if template_names.any?
      lines << "Anchor definitions detected: #{diagnostics[:alias_definitions].join(', ')}" if diagnostics[:alias_definitions].any?
      lines << "Alias references detected: #{diagnostics[:alias_references].join(', ')}" if diagnostics[:alias_references].any?
      lines
    end

    def relative_to_workspace(workspace, path)
      path.to_s.delete_prefix("#{workspace}/")
    end

    def extract_template_definitions(content)
      content.scan(/^(\.[A-Za-z0-9_.:-]+):(?:\s*(?:$|#))/).flatten
    end

    def extract_anchor_definitions(content)
      content.scan(/&([A-Za-z0-9_-]+)/).flatten
    end

    def extract_anchor_references(content)
      content.scan(/\*([A-Za-z0-9_-]+)/).flatten
    end

    def usage
      <<~TEXT
        Usage:
          gitlab-ci-auditor scan PATH [--format text|json|json-bundle|html|csv|pdf|sarif|junit] [--output FILE] [--policy FILE] [--policy-pack NAME] [--snapshot-file FILE] [--context-file FILE] [--history-file FILE] [--compare-to PATH]
          gitlab-ci-auditor flatten PATH [--snapshot-file FILE] [--output FILE]
          gitlab-ci-auditor serve [--host HOST] [--port PORT] [--policy FILE] [--policy-pack NAME] [--snapshot-file FILE] [--context-file FILE] [--history-file FILE]
          gitlab-ci-auditor list-packs
      TEXT
    end
  end
end
