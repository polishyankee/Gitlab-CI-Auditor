module GitlabCiAuditor
  class ReportRenderer
    def initialize(report)
      @report = report
    end

    def render_text
      lines = []
      lines << "GitLab CI SSDLC Audit"
      lines << "Pipeline: #{@report[:pipeline_path]}"
      lines << "Score: #{@report[:summary][:overall_score]}/#{@report[:summary][:max_score]} (#{@report[:summary][:grade]})"
      lines << "Status: #{@report[:summary][:status]}"
      lines << "Policy Pack: #{@report[:summary][:policy_pack_label]} (#{@report[:summary][:policy_source]})"
      lines << "Scope: #{@report[:summary][:analysis_scope]} (pipeline_files=#{@report[:summary][:total_pipeline_files]}, downstream_resolved=#{@report[:summary][:resolved_downstream_pipelines]}, downstream_unresolved=#{@report[:summary][:unresolved_downstream_pipelines]})"
      lines << ""
      lines << "Categories:"
      @report[:categories].each do |category|
        lines << "  - #{category[:title]}: #{category[:score]}/#{category[:max_score]} [#{category[:status]}] #{category[:summary]}"
      end
      lines << ""
      lines << "Scenario Results:"
      @report[:scenarios].each do |scenario|
        if scenario[:status] == "skipped"
          lines << "  - #{scenario[:label]}: skipped (#{scenario[:reason]})"
          next
        end

        control_bits = scenario[:controls].map { |key, state| "#{key}=#{state[:status]}" }.join(", ")
        lines << "  - #{scenario[:label]}: #{scenario[:status]} [#{control_bits}]"
      end
      lines << ""
      unless @report[:ssdlc_findings].empty?
        lines << "SSDLC Findings:"
        @report[:ssdlc_findings].each do |finding|
          lines << "  - [#{finding[:severity]}] #{finding[:title]}"
          lines << "    issue: #{finding[:issue]}"
          lines << "    recommendation: #{finding[:recommendation]}" if finding[:recommendation]
          lines << "    how_to_fix: #{finding[:how_to_fix]}" if finding[:how_to_fix]
        end
        lines << ""
      end
      unless @report[:security_findings].empty?
        lines << "Security Findings:"
        @report[:security_findings].each do |finding|
          lines << "  - [#{finding[:severity]}] #{finding[:title]}"
          lines << "    issue: #{finding[:issue]}"
          lines << "    recommendation: #{finding[:recommendation]}" if finding[:recommendation]
          lines << "    how_to_fix: #{finding[:how_to_fix]}" if finding[:how_to_fix]
        end
        lines << ""
      end
      unless @report[:recommendations].empty?
        lines << "Recommendations:"
        @report[:recommendations].each do |recommendation|
          lines << "  - #{recommendation}"
        end
      end
      lines.join("\n")
    end

    def render_html
      template = File.read(File.join(GitlabCiAuditor.root_dir, "templates", "report.html.erb"))
      ERB.new(template).result(binding)
    end
  end
end
