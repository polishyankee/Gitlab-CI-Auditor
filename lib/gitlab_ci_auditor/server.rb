module GitlabCiAuditor
  class Server
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
          res.body = <<~HTML
            <html>
              <body style="font-family: sans-serif; padding: 2rem">
                <h1>Analysis failed</h1>
                <p>#{ERB::Util.html_escape(error.message)}</p>
                <p><a href="/">Back</a></p>
              </body>
            </html>
          HTML
        end
      end

      trap("INT") { server.shutdown }
      trap("TERM") { server.shutdown }
      server.start
    end

    private

    def analyze_request(req)
      snapshot_file = req.query["snapshot_file_path"].to_s.strip
      snapshot_file = @snapshot_file if snapshot_file.empty?

      if req.query["pipeline_path"] && !req.query["pipeline_path"].to_s.strip.empty?
        pipeline_path = File.expand_path(req.query["pipeline_path"].to_s.strip)
        pipeline = PipelineLoader.new(snapshot_file: snapshot_file.empty? ? nil : snapshot_file).load(pipeline_path)
      elsif req.query["pipeline_file"]
        file = req.query["pipeline_file"]
        temp_path = File.join(Dir.tmpdir, ".gitlab-ci-upload-#{Process.pid}-#{Time.now.to_i}.yml")
        File.write(temp_path, file.to_s)
        pipeline = PipelineLoader.new(snapshot_file: snapshot_file.empty? ? nil : snapshot_file).load(temp_path)
      else
        raise ArgumentError, "Provide a pipeline path or upload a `.gitlab-ci.yml` file"
      end

      policy = load_policy(req.query["policy_pack"])
      Analyzer.new(pipeline, policy).analyze
    end

    def load_policy(requested_pack)
      return PolicyLoader.load(path: @policy_path) if @policy_path

      PolicyLoader.load(pack: requested_pack.to_s.strip.empty? ? @policy_pack : requested_pack)
    end
  end
end
