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
        policy_pack: PolicyLoader::DEFAULT_PACK
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: gitlab-ci-auditor scan PATH [--format text|json|html] [--output FILE] [--policy FILE] [--policy-pack NAME]"
        opts.on("--format FORMAT", "text, json, html") { |value| options[:format] = value }
        opts.on("--output FILE", "Write report to file") { |value| options[:output] = value }
        opts.on("--policy FILE", "Load custom policy JSON") { |value| options[:policy] = value }
        opts.on("--policy-pack NAME", "Use a bundled policy pack (default: #{PolicyLoader::DEFAULT_PACK})") { |value| options[:policy_pack] = value }
      end
      parser.parse!(argv)

      path = argv.shift
      raise ArgumentError, "Pipeline path is required" unless path

      policy = load_policy(options)
      pipeline = PipelineLoader.new.load(path)
      report = Analyzer.new(pipeline, policy).analyze
      renderer = ReportRenderer.new(report)
      output =
        case options[:format]
        when "json"
          JSON.pretty_generate(report)
        when "html"
          renderer.render_html
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
        policy_pack: PolicyLoader::DEFAULT_PACK
      }

      parser = OptionParser.new do |opts|
        opts.banner = "Usage: gitlab-ci-auditor serve [--host HOST] [--port PORT] [--policy FILE] [--policy-pack NAME]"
        opts.on("--host HOST", "Bind host") { |value| options[:host] = value }
        opts.on("--port PORT", Integer, "Bind port") { |value| options[:port] = value }
        opts.on("--policy FILE", "Load custom policy JSON") { |value| options[:policy] = value }
        opts.on("--policy-pack NAME", "Default bundled policy pack (default: #{PolicyLoader::DEFAULT_PACK})") { |value| options[:policy_pack] = value }
      end
      parser.parse!(argv)

      puts "Serving GitLab CI auditor on http://#{options[:host]}:#{options[:port]}"
      Server.new(host: options[:host], port: options[:port], policy_path: options[:policy], policy_pack: options[:policy_pack]).start
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
          gitlab-ci-auditor scan PATH [--format text|json|html] [--output FILE] [--policy FILE] [--policy-pack NAME]
          gitlab-ci-auditor serve [--host HOST] [--port PORT] [--policy FILE] [--policy-pack NAME]
          gitlab-ci-auditor list-packs
      TEXT
    end
  end
end
