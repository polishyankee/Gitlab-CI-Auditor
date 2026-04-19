begin
  require "webrick"
rescue LoadError
  raise LoadError, "The GUI server requires the `webrick` gem on modern Ruby releases. Install it with `gem install webrick` or use the Docker image."
end

require "fileutils"
require "open3"
require "tmpdir"

module GitlabCiAuditor
  class Server
    UploadDiagnostics = Struct.new(
      :selected_root,
      :root_candidates,
      :workspace_files,
      :template_definitions,
      :alias_definitions,
      :alias_references,
      keyword_init: true
    )

    ROOT_PIPELINE_FILENAMES = [
      ".gitlab-ci.yml",
      ".gitlab-ci.yaml",
      "gitlab-ci.yml",
      "gitlab-ci.yaml",
      "root.gitlabci.yml",
      "root.gitlab-ci.yml",
      "root.gitlab-ci.yaml"
    ].freeze

    def initialize(host:, port:, policy_path: nil, policy_pack: PolicyLoader::DEFAULT_PACK, snapshot_file: nil, context_file: nil, history_file: nil)
      @host = host
      @port = port
      @policy_path = policy_path
      @policy_pack = policy_pack
      @snapshot_file = snapshot_file
      @context_file = context_file
      @history_file = history_file
    end

    def start
      server = WEBrick::HTTPServer.new(
        Port: @port,
        BindAddress: @host,
        AccessLog: [],
        Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
      )

      server.mount_proc("/") do |_req, res|
        res["Content-Type"] = "text/html; charset=utf-8"
        res.body = render_index_page
      end

      server.mount_proc("/analyze") do |req, res|
        next unless req.request_method == "POST"

        begin
          report = analyze_request(req)
          res["Content-Type"] = "text/html; charset=utf-8"
          res.body = render_report_page(report, gui_export_enabled: true)
        rescue StandardError => error
          res.status = 422
          res["Content-Type"] = "text/html; charset=utf-8"
          res.body = render_error_page(error)
        end
      end

      server.mount_proc("/export") do |req, res|
        next unless req.request_method == "POST"

        begin
          export = build_export_response(req)
          res["Content-Type"] = export[:content_type]
          res["Content-Disposition"] = export[:content_disposition]
          res.body = export[:body]
        rescue StandardError => error
          res.status = 422
          res["Content-Type"] = "text/html; charset=utf-8"
          res.body = render_error_page(error)
        end
      end

      server.mount_proc("/validate-policy") do |req, res|
        next unless req.request_method == "POST"

        begin
          validation = validate_policy_request(req)
          res["Content-Type"] = "application/json; charset=utf-8"
          res.body = JSON.generate(validation)
        rescue StandardError => error
          res.status = 422
          res["Content-Type"] = "application/json; charset=utf-8"
          res.body = JSON.generate({ status: "error", error: error.message })
        end
      end

      trap("INT") { server.shutdown }
      trap("TERM") { server.shutdown }
      server.start
    end

    private

    def analyze_request(req)
      snapshot_file = resolved_snapshot_file(req.query["snapshot_file_path"])
      requested_context = req.query["context_file_path"]
      requested_history = req.query["history_file_path"]

      if req.query["pipeline_path"] && !req.query["pipeline_path"].to_s.strip.empty?
        pipeline_path = File.expand_path(req.query["pipeline_path"].to_s.strip)
        context_file = resolve_optional_file(requested_context, nil, @context_file)
        history_file = resolve_optional_file(requested_history, nil, @history_file)
        pipeline = ContextLoader.new(snapshot_file: snapshot_file, context_file: context_file).load(pipeline_path)
      elsif pasted_pipeline_present?(req)
        pipeline, context_file, history_file = load_pasted_pipeline(req, snapshot_file, requested_context, requested_history)
      elsif uploaded_pipeline_bundle_present?(req)
        pipeline, context_file, history_file = load_uploaded_pipeline(req, snapshot_file, requested_context, requested_history)
      else
        raise ArgumentError, "Provide a pipeline path, paste a root `.gitlab-ci.yml`, or upload a root `.gitlab-ci.yml`."
      end

      policy = load_policy(req.query["policy_ref"] || req.query["policy_pack"], req.query["policy_json"])
      report = Analyzer.new(pipeline, policy).analyze
      history_file ? HistoryStore.new(history_file).attach(report) : report
    end

    def resolved_snapshot_file(request_value)
      candidate = request_value.to_s.strip
      candidate = @snapshot_file.to_s.strip if candidate.empty?
      candidate.empty? ? nil : candidate
    end

    def resolve_optional_file(request_value, workspace = nil, default_value = nil)
      candidate = request_value.to_s.strip
      candidate = default_value.to_s.strip if candidate.empty?
      return nil if candidate.empty?

      if workspace && !candidate.start_with?("/")
        workspace_candidate = File.expand_path(candidate, workspace)
        return workspace_candidate if File.exist?(workspace_candidate)
      end

      File.expand_path(candidate)
    end

    def load_policy(requested_pack, inline_policy_json = nil)
      return PolicyLoader.load(path: @policy_path) if @policy_path

      inline_payload = inline_policy_json.to_s.strip
      unless inline_payload.empty?
        return PolicyLoader.load_json(
          inline_payload,
          source: "GUI policy editor",
          name: "gui_policy",
          label: "GUI Policy",
          policy_source: "gui_policy"
        )
      end

      selected_pack = requested_pack.to_s.strip
      selected_pack = @policy_pack if selected_pack.empty?
      selected_pack = selected_pack.delete_prefix("pack:") if selected_pack.start_with?("pack:")
      PolicyLoader.load(pack: selected_pack)
    end

    def render_index_page
      available_policy_entries = PolicyLoader.catalog_entries
      custom_policy_locked = !@policy_path.nil?
      default_policy_ref = "pack:#{@policy_pack}"
      default_policy_entry = available_policy_entries.find { |entry| entry[:id] == default_policy_ref } || available_policy_entries.first
      default_policy_catalog_json = JSON.generate(available_policy_entries).gsub("</", "<\\/")
      default_policy_json = default_policy_entry ? default_policy_entry[:json] : "{}"

      ERB.new(File.read(File.join(GitlabCiAuditor.root_dir, "templates", "index.html.erb"))).result(binding)
    end

    def render_report_page(report, gui_export_enabled: false)
      ReportRenderer.new(
        report,
        gui_export_enabled: gui_export_enabled,
        export_endpoint: "/export"
      ).render_html
    end

    def validate_policy_request(req)
      policy_name = sanitized_policy_name(req.query["policy_name"])
      policy_label = req.query["policy_label"].to_s.strip
      policy = PolicyLoader.load_json(
        req.query["policy_json"].to_s,
        source: "GUI policy editor",
        name: policy_name,
        label: policy_label.empty? ? policy_name : policy_label,
        policy_source: "gui_policy",
        force_meta: true
      )

      {
        status: "ok",
        policy_name: policy.dig("meta", "name"),
        policy_label: policy.dig("meta", "label"),
        pretty_json: JSON.pretty_generate(policy)
      }
    end

    def build_export_response(req)
      format = normalized_export_format(req.query["format"])
      report = deserialize_report_payload(req.query["report_payload"])
      renderer = ReportRenderer.new(report)
      export_filename = "#{export_filename_base(report)}#{export_extension_for(format)}"

      {
        body: export_body_for(renderer, format),
        content_type: export_content_type_for(format),
        content_disposition: %(attachment; filename="#{export_filename}")
      }
    end

    def export_body_for(renderer, format)
      case format
      when "text"
        renderer.render_text
      when "html"
        renderer.render_html
      when "csv"
        renderer.render_csv
      when "pdf"
        renderer.render_pdf
      when "json-bundle"
        renderer.render_json_bundle
      when "sarif"
        renderer.render_sarif
      when "junit"
        renderer.render_junit
      else
        raise ArgumentError, "Unsupported export format `#{format}`"
      end
    end

    def export_content_type_for(format)
      case format
      when "text"
        "text/plain; charset=utf-8"
      when "html"
        "text/html; charset=utf-8"
      when "csv"
        "text/csv; charset=utf-8"
      when "pdf"
        "application/pdf"
      when "json-bundle", "sarif"
        "application/json; charset=utf-8"
      when "junit"
        "application/xml; charset=utf-8"
      else
        "application/octet-stream"
      end
    end

    def export_extension_for(format)
      case format
      when "text"
        ".txt"
      when "html"
        ".html"
      when "csv"
        ".csv"
      when "pdf"
        ".pdf"
      when "json-bundle"
        ".bundle.json"
      when "sarif"
        ".sarif.json"
      when "junit"
        ".junit.xml"
      else
        ".bin"
      end
    end

    def normalized_export_format(value)
      candidate = value.to_s.strip.downcase
      candidate = "text" if candidate.empty?
      return "json-bundle" if %w[json_bundle bundle json-bundle].include?(candidate)
      return "junit" if %w[junit junit-xml xml].include?(candidate)

      candidate
    end

    def deserialize_report_payload(payload)
      decoded = Base64.strict_decode64(payload.to_s)
      GitlabCiAuditor.deep_symbolize_keys(JSON.parse(decoded))
    rescue ArgumentError, JSON::ParserError => e
      raise ArgumentError, "Invalid report payload for export: #{e.message}"
    end

    def export_filename_base(report)
      pipeline_name = File.basename(report[:pipeline_path].to_s.empty? ? "gitlab-ci-audit" : report[:pipeline_path].to_s)
      sanitized = pipeline_name.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
      sanitized.empty? ? "gitlab-ci-audit" : sanitized
    end

    def sanitized_policy_name(value)
      normalized = value.to_s.strip.downcase.gsub(/[^a-z0-9_-]+/, "_").gsub(/\A_+|_+\z/, "")
      raise ArgumentError, "Policy name is required" if normalized.empty?

      normalized
    end

    def uploaded_pipeline_bundle_present?(req)
      %w[pipeline_archive pipeline_file pipeline_support_files pipeline_directory_files].any? do |key|
        !normalized_upload_entries(req.query[key]).empty?
      end
    end

    def pasted_pipeline_present?(req)
      !req.query["pipeline_text"].to_s.strip.empty?
    end

    def load_pasted_pipeline(req, snapshot_file, requested_context = nil, requested_history = nil)
      Dir.mktmpdir(".gitlab-ci-paste-") do |workspace|
        filename = req.query["pipeline_text_filename"].to_s.strip
        relative_path = sanitized_upload_relative_path(filename, ".gitlab-ci.yml")
        pipeline_path = File.join(workspace, relative_path)
        FileUtils.mkdir_p(File.dirname(pipeline_path))
        content = normalize_pasted_yaml(req.query["pipeline_text"].to_s)
        File.write(pipeline_path, content)
        persist_pasted_support_files(workspace, req)

        context_file = resolve_optional_file(requested_context, workspace, @context_file)
        history_file = resolve_optional_file(requested_history, workspace, @history_file)
        pipeline = ContextLoader.new(snapshot_file: snapshot_file, context_file: context_file).load(pipeline_path)
        return [pipeline, context_file, history_file]
      end
    end

    def persist_pasted_support_files(workspace, req)
      paths = normalized_string_entries(req.query["pipeline_text_support_paths"])
      contents = normalized_string_entries(req.query["pipeline_text_support_contents"])

      [paths.length, contents.length].max.times do |index|
        content = contents[index].to_s
        next if content.strip.empty?

        relative_path = sanitized_upload_relative_path(paths[index], "support_#{index}.yml")
        absolute_path = File.join(workspace, relative_path)
        FileUtils.mkdir_p(File.dirname(absolute_path))
        File.write(absolute_path, normalize_pasted_yaml(content))
      end
    end

    def normalize_pasted_yaml(content)
      normalized = GitlabCiAuditor.sanitize_yaml_content(content)
      if normalized.lstrip.start_with?("#!")
        raise ArgumentError, "The pasted root pipeline looks like a shell script, not `.gitlab-ci.yml` content. Paste YAML only, or first run `gitlab-ci-auditor flatten PATH --output flat.gitlab-ci.yml` and then analyze the generated YAML."
      end

      normalized
    end

    def load_uploaded_pipeline(req, snapshot_file, requested_context = nil, requested_history = nil)
      diagnostics = nil

      with_uploaded_pipeline_workspace(req) do |pipeline_path, workspace|
        diagnostics = build_upload_diagnostics(workspace, pipeline_path)
        context_file = resolve_optional_file(requested_context, workspace, @context_file)
        history_file = resolve_optional_file(requested_history, workspace, @history_file)
        pipeline = ContextLoader.new(snapshot_file: snapshot_file, context_file: context_file).load(pipeline_path)
        [pipeline, context_file, history_file]
      end
    rescue ArgumentError => error
      raise rewrite_upload_error(error, diagnostics)
    end

    def with_uploaded_pipeline_workspace(req)
      archive_uploads = normalized_upload_entries(req.query["pipeline_archive"])
      root_uploads = normalized_upload_entries(req.query["pipeline_file"])
      support_uploads = normalized_upload_entries(req.query["pipeline_support_files"])
      support_paths = normalized_string_entries(req.query["pipeline_support_paths"])
      directory_uploads = normalized_upload_entries(req.query["pipeline_directory_files"])
      directory_paths = rebased_bundle_paths(normalized_string_entries(req.query["pipeline_directory_paths"]))

      Dir.mktmpdir(".gitlab-ci-upload-") do |workspace|
        root_pipeline_path = nil

        archive_uploads.each_with_index do |upload, index|
          extract_uploaded_archive(workspace, upload, index)
        end

        root_uploads.each_with_index do |upload, index|
          relative_path = sanitized_upload_relative_path(uploaded_relative_path(upload), index.zero? ? ".gitlab-ci.yml" : "pipeline_#{index}.yml")
          absolute_path = persist_uploaded_file(workspace, relative_path, upload)
          root_pipeline_path ||= absolute_path
        end

        support_uploads.each_with_index do |upload, index|
          relative_hint = support_paths[index]
          relative_path = sanitized_upload_relative_path(relative_hint || uploaded_relative_path(upload), "support_#{index}.yml")
          persist_uploaded_file(workspace, relative_path, upload)
        end

        directory_uploads.each_with_index do |upload, index|
          relative_hint = directory_paths[index]
          relative_path = sanitized_upload_relative_path(relative_hint || uploaded_relative_path(upload), "bundle_#{index}.yml")
          persist_uploaded_file(workspace, relative_path, upload)
        end

        explicit_root = req.query["pipeline_bundle_root"].to_s.strip
        root_pipeline_path = resolve_uploaded_root_pipeline_path(workspace, explicit_root, root_pipeline_path)
        yield(root_pipeline_path, workspace)
      end
    end

    def normalized_upload_entries(value)
      values = value.is_a?(Array) ? value.flatten : [value]
      values.compact.reject do |entry|
        upload_blank?(entry)
      end
    end

    def normalized_string_entries(value)
      values = value.is_a?(Array) ? value.flatten : [value]
      values.compact.map(&:to_s)
    end

    def rebased_bundle_paths(paths)
      return [] if paths.empty?

      segment_sets = paths.map { |path| normalized_relative_segments(path) }
      common_prefix = common_path_prefix(segment_sets)
      return segment_sets.map { |segments| File.join(segments) } if common_prefix.empty?

      segment_sets.map do |segments|
        trimmed_segments = segments[common_prefix.length..] || []
        File.join(*(trimmed_segments.empty? ? segments : trimmed_segments))
      end
    end

    def upload_blank?(entry)
      return true if entry.nil?

      filename = entry.respond_to?(:filename) ? entry.filename.to_s : ""
      filename.empty? && entry.to_s.empty?
    end

    def uploaded_relative_path(upload)
      return "" unless upload.respond_to?(:filename)

      upload.filename.to_s
    end

    def normalized_relative_segments(raw_path)
      candidate = raw_path.to_s.strip.tr("\\", "/").sub(%r{\A/+}, "")
      raise ArgumentError, "Unsafe uploaded file path #{raw_path.inspect}" if candidate.empty?

      segments = candidate.split("/").each_with_object([]) do |part, memo|
        next if part.empty? || part == "."

        raise ArgumentError, "Unsafe uploaded file path #{raw_path.inspect}" if part == ".."

        memo << part
      end

      raise ArgumentError, "Unsafe uploaded file path #{raw_path.inspect}" if segments.empty?

      segments
    end

    def common_path_prefix(segment_sets)
      prefix = []
      shortest_length = segment_sets.map(&:length).min.to_i

      shortest_length.times do |index|
        candidate = segment_sets.first[index]
        break unless segment_sets.all? { |segments| segments[index] == candidate }

        prefix << candidate
      end

      prefix
    end

    def sanitized_upload_relative_path(raw_path, fallback_name)
      candidate = raw_path.to_s.strip
      parts = candidate.empty? ? [fallback_name] : normalized_relative_segments(candidate)

      return fallback_name if parts.empty?

      File.join(parts)
    end

    def persist_uploaded_file(workspace, relative_path, upload)
      absolute_path = File.expand_path(relative_path, workspace)
      workspace_prefix = "#{workspace}#{File::SEPARATOR}"
      unless absolute_path == workspace || absolute_path.start_with?(workspace_prefix)
        raise ArgumentError, "Unsafe uploaded file path #{relative_path.inspect}"
      end

      FileUtils.mkdir_p(File.dirname(absolute_path))
      File.binwrite(absolute_path, uploaded_content(upload))
      absolute_path
    end

    def extract_uploaded_archive(workspace, upload, index)
      ensure_unzip_available!

      archive_name = uploaded_relative_path(upload)
      unless archive_name.downcase.end_with?(".zip")
        raise ArgumentError, "Unsupported pipeline archive #{archive_name.inspect}. Upload a `.zip` archive."
      end

      archive_path = File.join(workspace, ".pipeline-bundle-#{index}.zip")
      File.binwrite(archive_path, uploaded_content(upload))
      validate_archive_entries(archive_path)

      success = system("unzip", "-qq", archive_path, "-d", workspace, out: File::NULL, err: File::NULL)
      raise ArgumentError, "Failed to extract uploaded archive #{archive_name.inspect}" unless success
    end

    def uploaded_content(upload)
      if upload.respond_to?(:tempfile) && upload.tempfile
        upload.tempfile.rewind if upload.tempfile.respond_to?(:rewind)
        upload.tempfile.read
      else
        upload.to_s
      end
    end

    def ensure_unzip_available!
      return if system("unzip", "-v", out: File::NULL, err: File::NULL)

      raise ArgumentError, "ZIP upload requires the `unzip` command to be available on the server."
    end

    def validate_archive_entries(archive_path)
      listing, status = Open3.capture2("unzip", "-Z1", archive_path)
      raise ArgumentError, "Failed to inspect uploaded archive contents" unless status.success?

      listing.lines.map(&:strip).reject(&:empty?).each do |entry|
        next if entry.end_with?("/")

        sanitized_upload_relative_path(entry, "archive-entry.yml")
      end
    end

    def resolve_uploaded_root_pipeline_path(workspace, explicit_root, root_upload_path)
      return root_upload_path if root_upload_path && explicit_root.empty?

      candidates = uploaded_root_candidates(workspace)

      if !explicit_root.empty?
        relative_path = sanitized_upload_relative_path(explicit_root, ".gitlab-ci.yml")
        absolute_path = File.expand_path(relative_path, workspace)
        return absolute_path if File.file?(absolute_path)

        suffix_matches = candidates.select do |path|
          relative_candidate = path.delete_prefix("#{workspace}/")
          relative_candidate == relative_path || relative_candidate.end_with?("/#{relative_path}")
        end
        return suffix_matches.first if suffix_matches.size == 1

        raise ArgumentError, "Uploaded bundle does not contain root pipeline #{explicit_root.inspect}"
      end

      if candidates.empty?
        raise ArgumentError, "Could not determine the root pipeline inside the uploaded bundle. Upload the root `.gitlab-ci.yml` separately or set `Root pipeline path inside uploaded bundle`."
      end

      top_level_candidates = candidates.select { |path| File.dirname(path) == workspace }
      return top_level_candidates.first if top_level_candidates.size == 1
      return candidates.first if candidates.size == 1

      preferred_top_level = top_level_candidates.find { |path| File.basename(path).start_with?(".gitlab-ci.") }
      return preferred_top_level if preferred_top_level

      listed_candidates = candidates.first(5).map { |path| path.delete_prefix("#{workspace}/") }
      raise ArgumentError, "Uploaded bundle contains multiple root pipeline candidates (#{listed_candidates.join(', ')}). Set `Root pipeline path inside uploaded bundle` to choose one."
    end

    def rewrite_upload_error(error, diagnostics = nil)
      message = error.message.to_s
      guidance = "For large multi-file pipelines in GUI, flatten first with `./scripts/flatten_pipeline.sh PATH --output flat.gitlab-ci.yml` (or `gitlab-ci-auditor flatten`) and analyze the flattened file. Use CLI workflows for advanced multi-file or ZIP ingestion."
      diagnostics_lines = upload_diagnostics_lines(diagnostics)

      if message.include?("Unknown YAML alias `")
        return ArgumentError.new(([message] + diagnostics_lines).join("\n"))
      end

      if message.include?("extends unknown template")
        missing_template = message[/extends unknown template\s+(.+)$/, 1]
        template_hint =
          if diagnostics && missing_template && diagnostics.template_definitions.include?(missing_template)
            "Template `#{missing_template}` was found in the selected upload bundle. This usually means the visible `extends` error is secondary and the real cause is an earlier YAML issue or the wrong root pipeline selection."
          elsif diagnostics && !diagnostics.template_definitions.empty?
            "Hidden templates found in the selected upload bundle: #{diagnostics.template_definitions.join(', ')}"
          else
            nil
          end

        return ArgumentError.new(([message, template_hint] + diagnostics_lines + [guidance]).compact.join("\n"))
      end

      if message.include?("Pipeline file not found")
        return ArgumentError.new(([message] + diagnostics_lines + [guidance]).join("\n"))
      end

      error
    end

    def uploaded_root_candidates(workspace)
      Dir.glob(File.join(workspace, "**", "*"), File::FNM_DOTMATCH).select do |path|
        File.file?(path) && ROOT_PIPELINE_FILENAMES.include?(File.basename(path))
      end.sort_by do |path|
        relative_path = path.delete_prefix("#{workspace}/")
        [relative_path.count("/"), relative_path]
      end
    end

    def build_upload_diagnostics(workspace, selected_root_path)
      workspace_files = Dir.glob(File.join(workspace, "**", "*"), File::FNM_DOTMATCH).select { |path| File.file?(path) }
      yaml_files = workspace_files.select { |path| %w[.yml .yaml].include?(File.extname(path)) }

      UploadDiagnostics.new(
        selected_root: relative_to_workspace(workspace, selected_root_path),
        root_candidates: uploaded_root_candidates(workspace).map { |path| relative_to_workspace(workspace, path) },
        workspace_files: yaml_files.map { |path| relative_to_workspace(workspace, path) }.sort.first(12),
        template_definitions: yaml_files.flat_map { |path| extract_template_definitions(File.read(path)) }.uniq.sort.first(20),
        alias_definitions: yaml_files.flat_map { |path| extract_anchor_definitions(File.read(path)) }.uniq.sort.first(20),
        alias_references: yaml_files.flat_map { |path| extract_anchor_references(File.read(path)) }.uniq.sort.first(20)
      )
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

    def upload_diagnostics_lines(diagnostics)
      return [] unless diagnostics

      lines = []
      lines << "Selected root pipeline: #{diagnostics.selected_root}" if diagnostics.selected_root
      lines << "Root candidates detected in upload: #{diagnostics.root_candidates.join(', ')}" if diagnostics.root_candidates.any?
      lines << "YAML files detected in upload: #{diagnostics.workspace_files.join(', ')}" if diagnostics.workspace_files.any?
      lines << "Hidden templates detected: #{diagnostics.template_definitions.join(', ')}" if diagnostics.template_definitions.any?
      lines << "Anchor definitions detected: #{diagnostics.alias_definitions.join(', ')}" if diagnostics.alias_definitions.any?
      lines << "Alias references detected: #{diagnostics.alias_references.join(', ')}" if diagnostics.alias_references.any?
      lines
    end

    def render_error_page(error)
      <<~HTML
        <html>
          <body style="font-family: sans-serif; padding: 2rem">
            <h1>Analysis failed</h1>
            <pre style="white-space: pre-wrap; line-height: 1.55; background: #f6f8fa; border: 1px solid #d0d7de; border-radius: 12px; padding: 1rem;">#{ERB::Util.html_escape(error.message)}</pre>
            <p><a href="/">Back</a></p>
          </body>
        </html>
      HTML
    end
  end
end
