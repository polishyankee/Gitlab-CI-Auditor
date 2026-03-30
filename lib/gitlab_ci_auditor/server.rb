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

    def initialize(host:, port:, policy_path: nil, policy_pack: PolicyLoader::DEFAULT_PACK, snapshot_file: nil)
      @host = host
      @port = port
      @policy_path = policy_path
      @policy_pack = policy_pack
      @snapshot_file = snapshot_file
    end

    def start
      server = WEBrick::HTTPServer.new(
        Port: @port,
        BindAddress: @host,
        AccessLog: [],
        Logger: WEBrick::Log.new($stderr, WEBrick::Log::WARN)
      )

      server.mount_proc("/") do |_req, res|
        available_policy_packs = PolicyLoader.available_packs
        selected_policy_pack = @policy_pack
        custom_policy_locked = !@policy_path.nil?
        default_snapshot_file = @snapshot_file.to_s
        res["Content-Type"] = "text/html; charset=utf-8"
        res.body = ERB.new(File.read(File.join(GitlabCiAuditor.root_dir, "templates", "index.html.erb"))).result(binding)
      end

      server.mount_proc("/analyze") do |req, res|
        next unless req.request_method == "POST"

        begin
          report = analyze_request(req)
          res["Content-Type"] = "text/html; charset=utf-8"
          res.body = ReportRenderer.new(report).render_html
        rescue StandardError => error
          res.status = 422
          res["Content-Type"] = "text/html; charset=utf-8"
          res.body = render_error_page(error)
        end
      end

      trap("INT") { server.shutdown }
      trap("TERM") { server.shutdown }
      server.start
    end

    private

    def analyze_request(req)
      snapshot_file = resolved_snapshot_file(req.query["snapshot_file_path"])

      if req.query["pipeline_path"] && !req.query["pipeline_path"].to_s.strip.empty?
        pipeline_path = File.expand_path(req.query["pipeline_path"].to_s.strip)
        pipeline = PipelineLoader.new(snapshot_file: snapshot_file).load(pipeline_path)
      elsif uploaded_pipeline_bundle_present?(req)
        pipeline = load_uploaded_pipeline(req, snapshot_file)
      else
        raise ArgumentError, "Provide a pipeline path, upload a root `.gitlab-ci.yml`, or upload a pipeline directory bundle"
      end

      policy = load_policy(req.query["policy_pack"])
      Analyzer.new(pipeline, policy).analyze
    end

    def resolved_snapshot_file(request_value)
      candidate = request_value.to_s.strip
      candidate = @snapshot_file.to_s.strip if candidate.empty?
      candidate.empty? ? nil : candidate
    end

    def load_policy(requested_pack)
      return PolicyLoader.load(path: @policy_path) if @policy_path

      PolicyLoader.load(pack: requested_pack.to_s.strip.empty? ? @policy_pack : requested_pack)
    end

    def uploaded_pipeline_bundle_present?(req)
      %w[pipeline_archive pipeline_file pipeline_support_files pipeline_directory_files].any? do |key|
        !normalized_upload_entries(req.query[key]).empty?
      end
    end

    def load_uploaded_pipeline(req, snapshot_file)
      diagnostics = nil

      with_uploaded_pipeline_workspace(req) do |pipeline_path, workspace|
        diagnostics = build_upload_diagnostics(workspace, pipeline_path)
        PipelineLoader.new(snapshot_file: snapshot_file).load(pipeline_path)
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
      guidance = "Upload the root `.gitlab-ci.yml` together with every local include/template file, upload the whole pipeline directory and set `Root pipeline path inside uploaded bundle`, or upload a `.zip` archive that contains `.gitlab-ci.yml` or `root.gitlabci.yml`. For nested support files, provide bundle-relative paths that match the original repository layout."
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
