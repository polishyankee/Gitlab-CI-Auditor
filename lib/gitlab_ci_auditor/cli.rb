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
        snapshot_file: nil
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: gitlab-ci-auditor scan PATH [--format text|json|json-bundle|html|csv|pdf] [--output FILE] [--policy FILE] [--policy-pack NAME] [--snapshot-file FILE]"
        opts.on("--format FORMAT", "text, json, json-bundle, html, csv, pdf") { |value| options[:format] = value }
        opts.on("--output FILE", "Write report to file") { |value| options[:output] = value }
        opts.on("--policy FILE", "Load custom policy JSON") { |value| options[:policy] = value }
        opts.on("--policy-pack NAME", "Use a bundled policy pack (default: #{PolicyLoader::DEFAULT_PACK})") { |value| options[:policy_pack] = value }
        opts.on("--snapshot-file FILE", "Load downstream snapshot mappings from JSON") { |value| options[:snapshot_file] = value }
      end
      parser.parse!(argv)

      path = argv.shift
      raise ArgumentError, "Pipeline path is required" unless path
      raise ArgumentError, "PDF output requires --output FILE" if options[:format] == "pdf" && options[:output].nil?

      policy = load_policy(options)
      pipeline = PipelineLoader.new(snapshot_file: options[:snapshot_file]).load(path)
      report = Analyzer.new(pipeline, policy).analyze
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

    def serve(argv)
      options = {
        host: "127.0.0.1",
        port: 4567,
        policy: nil,
        policy_pack: PolicyLoader::DEFAULT_PACK,
        snapshot_file: nil
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: gitlab-ci-auditor serve [--host HOST] [--port PORT] [--policy FILE] [--policy-pack NAME] [--snapshot-file FILE]"
        opts.on("--host HOST", "Bind host") { |value| options[:host] = value }
        opts.on("--port PORT", Integer, "Bind port") { |value| options[:port] = value }
        opts.on("--policy FILE", "Load custom policy JSON") { |value| options[:policy] = value }
        opts.on("--policy-pack NAME", "Default bundled policy pack (default: #{PolicyLoader::DEFAULT_PACK})") { |value| options[:policy_pack] = value }
        opts.on("--snapshot-file FILE", "Default downstream snapshot manifest for GUI analysis") { |value| options[:snapshot_file] = value }
      end
      parser.parse!(argv)

      GitlabCiAuditor.require_server!

      puts "Serving GitLab CI auditor on http://#{options[:host]}:#{options[:port]}"
      Server.new(
        host: options[:host],
        port: options[:port],
        policy_path: options[:policy],
        policy_pack: options[:policy_pack],
        snapshot_file: options[:snapshot_file]
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

    def usage
      <<~TEXT
        Usage:
          gitlab-ci-auditor scan PATH [--format text|json|json-bundle|html|csv|pdf] [--output FILE] [--policy FILE] [--policy-pack NAME] [--snapshot-file FILE]
          gitlab-ci-auditor serve [--host HOST] [--port PORT] [--policy FILE] [--policy-pack NAME] [--snapshot-file FILE]
          gitlab-ci-auditor list-packs
      TEXT
    end
  end
end
