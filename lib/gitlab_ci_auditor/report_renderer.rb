module GitlabCiAuditor
  class ReportRenderer
    class SimplePdfDocument
      PAGE_WIDTH = 595
      PAGE_HEIGHT = 842
      FONT_SIZE = 10
      LINE_HEIGHT = 14
      LEFT_MARGIN = 40
      TOP_MARGIN = 792
      LINES_PER_PAGE = 52

      def initialize(text)
        @text = text
      end

      def render
        lines = @text.split("\n")
        lines = [" "] if lines.empty?
        page_chunks = lines.each_slice(LINES_PER_PAGE).to_a

        objects = []
        objects[1] = "<< /Type /Catalog /Pages 2 0 R >>"
        page_ids = []
        content_ids = []
        next_id = 3

        page_chunks.each do |_chunk|
          page_ids << next_id
          content_ids << (next_id + 1)
          next_id += 2
        end

        objects[2] = "<< /Type /Pages /Count #{page_ids.size} /Kids [ #{page_ids.map { |id| "#{id} 0 R" }.join(' ')} ] >>"

        page_chunks.each_with_index do |chunk, index|
          page_id = page_ids[index]
          content_id = content_ids[index]
          objects[page_id] = "<< /Type /Page /Parent 2 0 R /MediaBox [0 0 #{PAGE_WIDTH} #{PAGE_HEIGHT}] /Resources << /Font << /F1 #{next_id} 0 R >> >> /Contents #{content_id} 0 R >>"
          stream = build_stream(chunk)
          objects[content_id] = "<< /Length #{stream.bytesize} >>\nstream\n#{stream}\nendstream"
        end

        objects[next_id] = "<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>"

        pdf = +"%PDF-1.4\n"
        offsets = Array.new(objects.length, 0)
        (1...objects.length).each do |id|
          next unless objects[id]

          offsets[id] = pdf.bytesize
          pdf << "#{id} 0 obj\n#{objects[id]}\nendobj\n"
        end

        xref_offset = pdf.bytesize
        pdf << "xref\n0 #{objects.length}\n"
        pdf << "0000000000 65535 f \n"
        (1...objects.length).each do |id|
          if objects[id]
            pdf << format("%010d 00000 n \n", offsets[id])
          else
            pdf << "0000000000 65535 f \n"
          end
        end
        pdf << "trailer\n<< /Size #{objects.length} /Root 1 0 R >>\nstartxref\n#{xref_offset}\n%%EOF\n"
        pdf
      end

      private

      def build_stream(lines)
        escaped_lines = lines.map { |line| pdf_escape(line) }
        body = []
        body << "BT"
        body << "/F1 #{FONT_SIZE} Tf"
        body << "#{LINE_HEIGHT} TL"
        body << "#{LEFT_MARGIN} #{TOP_MARGIN} Td"
        escaped_lines.each_with_index do |line, index|
          body << "(#{line}) Tj"
          body << "T*" unless index == escaped_lines.length - 1
        end
        body << "ET"
        body.join("\n")
      end

      def pdf_escape(value)
        value.to_s.encode("Windows-1252", invalid: :replace, undef: :replace, replace: "?").gsub(/[\\()]/) { |match| "\\#{match}" }
      end
    end

    def initialize(report)
      @report = report
    end

    def render_json_bundle
      JSON.pretty_generate(
        {
          meta: {
            exporter_version: GitlabCiAuditor::VERSION,
            generated_at: Time.now.utc.iso8601,
            format: "json_bundle"
          },
          report: @report,
          exports: {
            text: render_text
          }
        }
      )
    end

    def render_text
      lines = []
      lines << "GitLab CI SSDLC Audit"
      lines << "Pipeline: #{@report[:pipeline_path]}"
      lines << "Score: #{@report[:summary][:overall_score]}/#{@report[:summary][:max_score]} (#{@report[:summary][:grade]})"
      lines << "Status: #{@report[:summary][:status]}"
      lines << "Policy Pack: #{@report[:summary][:policy_pack_label]} (#{@report[:summary][:policy_source]})"
      lines << "Scope: #{@report[:summary][:analysis_scope]} (pipeline_files=#{@report[:summary][:total_pipeline_files]}, downstream_resolved=#{@report[:summary][:resolved_downstream_pipelines]}, downstream_unresolved=#{@report[:summary][:unresolved_downstream_pipelines]})"
      if @report[:diff].is_a?(Hash) && @report[:diff][:enabled]
        diff = @report[:diff]
        lines << "Diff vs: #{diff.dig(:baseline, :pipeline_path)}"
        lines << "Score Delta: #{diff[:score_delta]}"
        lines << "Baseline Grade: #{diff.dig(:baseline, :grade)}"
        lines << "Current Grade: #{diff.dig(:current, :grade)}"
      end
      if @report.dig(:metadata, :context_manifest)
        lines << "Context Manifest: #{@report.dig(:metadata, :context_manifest)}"
        lines << "Context Projects: #{Array(@report.dig(:metadata, :context_projects)).join(', ')}" if Array(@report.dig(:metadata, :context_projects)).any?
      end
      lines << ""
      if @report[:lint].is_a?(Hash)
        lines << "Lint:"
        lines << "  - status: #{@report.dig(:lint, :status)}"
        lines << "  - summary: #{@report.dig(:lint, :summary)}"
        Array(@report.dig(:lint, :findings)).each do |finding|
          lines << "    finding [#{finding[:status]}]: #{finding[:message]}"
        end
        lines << ""
      end
      lines << ""
      if @report[:diff].is_a?(Hash) && @report[:diff][:enabled]
        diff = @report[:diff]
        lines << "Diff Summary:"
        Array(diff[:highlights]).each do |item|
          lines << "  - #{item}"
        end
        Array(diff[:category_deltas]).first(8).each do |delta|
          lines << "  - category #{delta[:title]}: current=#{delta[:current_score]}/#{delta[:current_max_score]} baseline=#{delta[:baseline_score]}/#{delta[:baseline_max_score]} delta=#{delta[:delta]}"
        end
        diff.fetch(:finding_deltas, {}).each do |section, finding_delta|
          lines << "  - #{section} added: #{Array(finding_delta[:added]).map { |item| item[:title] }.join(' | ')}" if Array(finding_delta[:added]).any?
          lines << "  - #{section} resolved: #{Array(finding_delta[:resolved]).map { |item| item[:title] }.join(' | ')}" if Array(finding_delta[:resolved]).any?
          Array(finding_delta[:severity_changed]).each do |change|
            lines << "  - #{section} severity changed: #{change[:title]} #{change[:baseline_severity]} -> #{change[:current_severity]}"
          end
        end
        lines << ""
      end

      lines << ""
      lines << "Categories:"
      @report[:categories].each do |category|
        lines << "  - #{category[:title]}: #{category[:score]}/#{category[:max_score]} [#{category[:status]}] #{category[:summary]}"
      end
      lines << ""
      lines << "OWASP SAMM v2:"
      @report.fetch(:benchmarks, {}).fetch(:owasp_samm_v2, {}).fetch(:observed_signals, []).each do |signal_group|
        lines << "  observed #{signal_group[:label]}: #{signal_group[:values].join(' | ')}"
      end
      @report.fetch(:benchmarks, {}).fetch(:owasp_samm_v2, {}).fetch(:practices, []).each do |practice|
        lines << "  - #{practice[:title]}: level #{practice[:estimated_level]}/#{practice[:max_level]} [#{practice[:status]}] alignment=#{practice[:alignment_score]}/100 confidence=#{practice[:confidence]}"
        lines << "    rationale: #{practice[:rationale]}"
        practice.fetch(:rules, []).each do |rule|
          lines << "    rule [#{rule[:status]}]: #{rule[:title]} - #{rule[:detail]}"
        end
        summary = practice.fetch(:question_summary, {})
        lines << "    questions: #{summary.fetch(:pass, 0)} pass, #{summary.fetch(:warn, 0)} warn, #{summary.fetch(:fail, 0)} fail, #{summary.fetch(:review, 0)} review"
        practice.fetch(:questions, []).each do |question|
          lines << "    question [#{question[:status]}] #{question[:key]} (#{question[:observability]}): #{question[:title]}"
          lines << "      detail: #{question[:detail]}"
          lines << "      recommendation: #{question[:recommendation]}" if question[:recommendation]
        end
      end
      if @report[:history].is_a?(Hash) && @report[:history][:enabled]
        history = @report[:history]
        lines << ""
        lines << "Historical Trends:"
        lines << "  - History file: #{history[:path]}"
        lines << "  - Total stored runs: #{history[:total_runs]}"
        lines << "  - Previous score: #{history[:previous_score] || 'n/a'}"
        lines << "  - Score delta: #{history[:score_delta] || 'n/a'}"
        Array(history[:recent_runs]).each do |run|
          lines << "    recent: #{run[:generated_at]} score=#{run[:overall_score]}/#{run[:max_score]} grade=#{run[:grade]} policy=#{run[:policy_pack_name]}"
        end
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

    def render_csv
      CSV.generate do |csv|
        csv << %w[row_type section key label status severity score max_score summary issue recommendation how_to_fix evidence]
        csv << ["summary", "report", "overall", @report[:pipeline_path], @report[:summary][:status], nil, @report[:summary][:overall_score], @report[:summary][:max_score], "grade=#{@report[:summary][:grade]}; policy_pack=#{@report[:summary][:policy_pack_label]}; scope=#{@report[:summary][:analysis_scope]}", nil, nil, nil, nil]
        if @report[:diff].is_a?(Hash) && @report[:diff][:enabled]
          diff = @report[:diff]
          csv << ["diff", "diff", "summary", diff.dig(:baseline, :pipeline_path), diff.dig(:current, :status), nil, diff[:score_delta], diff[:max_score_delta], "baseline_grade=#{diff.dig(:baseline, :grade)}; current_grade=#{diff.dig(:current, :grade)}", nil, nil, nil, nil]
          Array(diff[:category_deltas]).each do |delta|
            csv << ["diff_category", "diff", delta[:key], delta[:title], delta[:current_status], nil, delta[:current_score], delta[:current_max_score], "baseline_score=#{delta[:baseline_score]}; baseline_status=#{delta[:baseline_status]}; delta=#{delta[:delta]}", nil, nil, nil, nil]
          end
          diff.fetch(:finding_deltas, {}).each do |section, finding_delta|
            Array(finding_delta[:added]).each do |finding|
              csv << ["diff_finding", "diff_#{section}", "added", finding[:title], nil, finding[:severity], nil, nil, finding[:issue], nil, nil, nil, nil]
            end
            Array(finding_delta[:resolved]).each do |finding|
              csv << ["diff_finding", "diff_#{section}", "resolved", finding[:title], nil, finding[:severity], nil, nil, finding[:issue], nil, nil, nil, nil]
            end
            Array(finding_delta[:severity_changed]).each do |change|
              csv << ["diff_finding", "diff_#{section}", "severity_changed", change[:title], nil, change[:current_severity], nil, nil, "baseline_severity=#{change[:baseline_severity]}; current_severity=#{change[:current_severity]}", change[:baseline_issue], change[:current_issue], nil, nil]
            end
          end
        end

        if @report[:lint].is_a?(Hash)
          csv << ["lint", "lint", "summary", @report[:lint][:title], @report[:lint][:status], nil, @report[:lint][:score], @report[:lint][:max_score], @report[:lint][:summary], nil, nil, nil, nil]
          Array(@report[:lint][:findings]).each_with_index do |finding, index|
            csv << ["lint_finding", "lint", index.to_s, finding[:message], finding[:status], nil, nil, nil, nil, nil, nil, nil, Array(finding[:evidence]).join(" | ")]
          end
        end

        @report[:categories].each do |category|
          csv << ["category", "categories", category[:key], category[:title], category[:status], nil, category[:score], category[:max_score], category[:summary], nil, nil, nil, nil]
        end

        if @report[:history].is_a?(Hash) && @report[:history][:enabled]
          history = @report[:history]
          csv << ["history", "history", "summary", "Historical Trend", nil, nil, nil, nil, "total_runs=#{history[:total_runs]}; previous_score=#{history[:previous_score]}; score_delta=#{history[:score_delta]}", nil, nil, nil, history[:path]]
          Array(history[:recent_runs]).each_with_index do |run, index|
            csv << ["history_run", "history", index.to_s, run[:generated_at], run[:status], nil, run[:overall_score], run[:max_score], "grade=#{run[:grade]}; policy_pack=#{run[:policy_pack_name]}", nil, nil, nil, nil]
          end
        end

        @report.fetch(:benchmarks, {}).fetch(:owasp_samm_v2, {}).fetch(:practices, []).each do |practice|
          csv << ["benchmark", "owasp_samm_v2", practice[:key], practice[:title], practice[:status], nil, practice[:alignment_score], 100, "level=#{practice[:estimated_level]}/#{practice[:max_level]}; confidence=#{practice[:confidence]}; reference=#{practice[:reference_url]}", practice[:rationale], Array(practice[:good_signals]).join(" | "), Array(practice[:gaps]).join(" | "), nil]
          practice.fetch(:questions, []).each do |question|
            csv << ["benchmark_question", "owasp_samm_v2", question[:key], question[:title], question[:status], question[:observability], nil, nil, question[:detail], nil, question[:recommendation], question[:static_limitations], question[:source_url]]
          end
        end

        @report[:scenarios].each do |scenario|
          controls = scenario[:status] == "skipped" ? nil : scenario[:controls].map { |key, state| "#{key}=#{state[:status]}" }.join("; ")
          csv << ["scenario", "scenarios", scenario[:id], scenario[:label], scenario[:status], nil, nil, nil, controls, scenario[:reason], nil, nil, Array(scenario[:changed_files]).join(" | ")]
        end

        @report[:ssdlc_findings].each do |finding|
          csv << ["finding", "ssdlc", nil, finding[:title], nil, finding[:severity], nil, nil, nil, finding[:issue], finding[:recommendation], finding[:how_to_fix], Array(finding[:evidence]).join(" | ")]
        end

        @report[:security_findings].each do |finding|
          csv << ["finding", "security", nil, finding[:title], nil, finding[:severity], nil, nil, nil, finding[:issue], finding[:recommendation], finding[:how_to_fix], Array(finding[:evidence]).join(" | ")]
        end
      end
    end

    def render_sarif
      entries = sarif_entries

      JSON.pretty_generate(
        {
          "$schema" => "https://json.schemastore.org/sarif-2.1.0.json",
          "version" => "2.1.0",
          "runs" => [
            {
              "tool" => {
                "driver" => {
                  "name" => "GitLab CI SSDLC Auditor",
                  "informationUri" => "https://github.com/polishyankee/Gitlab-CI-Auditor",
                  "version" => GitlabCiAuditor::VERSION,
                  "rules" => sarif_rules(entries)
                }
              },
              "results" => entries.map { |entry| sarif_result(entry) },
              "properties" => {
                "pipeline_path" => @report[:pipeline_path],
                "generated_at" => @report[:generated_at],
                "overall_score" => @report.dig(:summary, :overall_score),
                "max_score" => @report.dig(:summary, :max_score),
                "grade" => @report.dig(:summary, :grade),
                "status" => @report.dig(:summary, :status),
                "policy_pack" => @report.dig(:summary, :policy_pack_name),
                "analysis_scope" => @report.dig(:summary, :analysis_scope)
              }
            }
          ]
        }
      )
    end

    def render_junit
      suites = junit_suites
      testcases = suites.flat_map { |suite| suite[:testcases] }
      tests = testcases.size
      failures = testcases.count { |testcase| testcase[:status] == "fail" }
      skipped = testcases.count { |testcase| testcase[:status] == "warn" }

      lines = []
      lines << %(<?xml version="1.0" encoding="UTF-8"?>)
      lines << %(<testsuites name="GitLab CI SSDLC Auditor" tests="#{tests}" failures="#{failures}" skipped="#{skipped}">)
      suites.each do |suite|
        suite_tests = suite[:testcases].size
        suite_failures = suite[:testcases].count { |testcase| testcase[:status] == "fail" }
        suite_skipped = suite[:testcases].count { |testcase| testcase[:status] == "warn" }
        lines << %(  <testsuite name="#{xml_escape(suite[:name])}" tests="#{suite_tests}" failures="#{suite_failures}" skipped="#{suite_skipped}" time="0">)
        properties = suite[:properties].to_h.reject { |_key, value| value.nil? }
        if properties.any?
          lines << %(    <properties>)
          properties.each do |key, value|
            lines << %(      <property name="#{xml_escape(key)}" value="#{xml_escape(value)}"/>)
          end
          lines << %(    </properties>)
        end
        suite[:testcases].each do |testcase|
          lines << %(    <testcase classname="#{xml_escape(testcase[:classname])}" name="#{xml_escape(testcase[:name])}" time="0">)
          case testcase[:status]
          when "fail"
            lines << %(      <failure type="#{xml_escape(testcase[:type])}" message="#{xml_escape(testcase[:message])}"/>)
          when "warn"
            lines << %(      <skipped message="#{xml_escape(testcase[:message])}"/>)
          end
          lines << %(      <system-out>#{xml_escape(testcase[:detail])}</system-out>) unless testcase[:detail].to_s.empty?
          lines << %(    </testcase>)
        end
        lines << %(  </testsuite>)
      end
      lines << %(</testsuites>)
      lines.join("\n")
    end

    def render_html
      template = File.read(File.join(GitlabCiAuditor.root_dir, "templates", "report.html.erb"))
      ERB.new(template).result(binding)
    end

    def render_pdf
      SimplePdfDocument.new(render_text).render
    end

    private

    def sarif_entries
      entries = []

      Array(@report.dig(:lint, :findings)).each do |finding|
        next if finding[:status].to_s == "pass"

        entries << {
          section: "lint",
          title: finding[:message].to_s,
          message: finding[:message].to_s,
          level: sarif_level_for_status(finding[:status]),
          severity: severity_for_lint_status(finding[:status]),
          recommendation: "Resolve the structural pipeline issue and rerun the auditor.",
          how_to_fix: Array(finding[:evidence]).any? ? "Inspect the attached evidence and reconcile the pipeline structure with the original repository layout." : nil,
          evidence: Array(finding[:evidence])
        }
      end

      %w[ssdlc security].each do |section|
        Array(@report[:"#{section}_findings"]).each do |finding|
          entries << {
            section: section,
            title: finding[:title].to_s,
            message: finding[:issue].to_s.empty? ? finding[:title].to_s : finding[:issue].to_s,
            level: sarif_level_for_severity(finding[:severity]),
            severity: finding[:severity].to_s,
            recommendation: finding[:recommendation],
            how_to_fix: finding[:how_to_fix],
            evidence: Array(finding[:evidence]),
            severity_source: finding[:severity_source],
            base_severity: finding[:base_severity]
          }
        end
      end

      entries.map do |entry|
        entry.merge(rule_id: sarif_rule_id(entry[:section], entry[:title]))
      end
    end

    def sarif_rules(entries)
      entries.uniq { |entry| entry[:rule_id] }.map do |entry|
        {
          "id" => entry[:rule_id],
          "name" => entry[:title],
          "shortDescription" => { "text" => entry[:title] },
          "fullDescription" => { "text" => entry[:message] },
          "help" => { "text" => sarif_help_text(entry) },
          "properties" => {
            "section" => entry[:section],
            "default_severity" => entry[:severity]
          }
        }
      end
    end

    def sarif_result(entry)
      {
        "ruleId" => entry[:rule_id],
        "level" => entry[:level],
        "message" => { "text" => entry[:message] },
        "locations" => [
          {
            "physicalLocation" => {
              "artifactLocation" => { "uri" => @report[:pipeline_path] }
            }
          }
        ],
        "properties" => {
          "section" => entry[:section],
          "severity" => entry[:severity],
          "severity_source" => entry[:severity_source],
          "base_severity" => entry[:base_severity],
          "recommendation" => entry[:recommendation],
          "how_to_fix" => entry[:how_to_fix],
          "evidence" => entry[:evidence]
        }.reject { |_key, value| value.nil? || (value.respond_to?(:empty?) && value.empty?) }
      }
    end

    def sarif_help_text(entry)
      [
        entry[:recommendation],
        entry[:how_to_fix]
      ].compact.join("\n\n")
    end

    def sarif_rule_id(section, title)
      "#{section}/#{slugify(title)}"
    end

    def sarif_level_for_severity(severity)
      case severity.to_s
      when "high"
        "error"
      when "medium"
        "warning"
      else
        "note"
      end
    end

    def sarif_level_for_status(status)
      case status.to_s
      when "fail"
        "error"
      when "warn"
        "warning"
      else
        "note"
      end
    end

    def severity_for_lint_status(status)
      case status.to_s
      when "fail"
        "high"
      when "warn"
        "medium"
      else
        "low"
      end
    end

    def junit_suites
      [
        {
          name: "summary",
          properties: junit_common_properties,
          testcases: [
            {
              classname: "summary",
              name: "Overall Score",
              status: junit_status_for_report(@report.dig(:summary, :status)),
              type: "report_summary",
              message: "Overall score #{@report.dig(:summary, :overall_score)}/#{@report.dig(:summary, :max_score)} (#{@report.dig(:summary, :grade)})",
              detail: "policy_pack=#{@report.dig(:summary, :policy_pack_label)}; scope=#{@report.dig(:summary, :analysis_scope)}; pipeline=#{@report[:pipeline_path]}"
            }
          ]
        },
        {
          name: "categories",
          properties: junit_common_properties,
          testcases: Array(@report[:categories]).map do |category|
            {
              classname: "category",
              name: category[:title].to_s,
              status: junit_status_for_report(category[:status]),
              type: "category",
              message: category[:summary].to_s,
              detail: "score=#{category[:score]}/#{category[:max_score]}; key=#{category[:key]}; status=#{category[:status]}"
            }
          end
        },
        {
          name: "lint",
          properties: junit_common_properties,
          testcases: junit_lint_testcases
        },
        {
          name: "ssdlc",
          properties: junit_common_properties,
          testcases: junit_finding_testcases("ssdlc", Array(@report[:ssdlc_findings]))
        },
        {
          name: "security",
          properties: junit_common_properties,
          testcases: junit_finding_testcases("security", Array(@report[:security_findings]))
        }
      ]
    end

    def junit_common_properties
      {
        "pipeline_path" => @report[:pipeline_path],
        "generated_at" => @report[:generated_at],
        "overall_score" => @report.dig(:summary, :overall_score),
        "grade" => @report.dig(:summary, :grade),
        "policy_pack" => @report.dig(:summary, :policy_pack_name)
      }
    end

    def junit_lint_testcases
      findings = Array(@report.dig(:lint, :findings))
      return [junit_pass_placeholder("lint", "No lint findings")] if findings.empty?

      findings.map do |finding|
        {
          classname: "lint",
          name: finding[:message].to_s,
          status: junit_status_for_report(finding[:status]),
          type: "lint",
          message: finding[:message].to_s,
          detail: Array(finding[:evidence]).join(" | ")
        }
      end
    end

    def junit_finding_testcases(section, findings)
      return [junit_pass_placeholder(section, "No #{section} findings")] if findings.empty?

      findings.map do |finding|
        {
          classname: section,
          name: finding[:title].to_s,
          status: junit_status_for_severity(finding[:severity]),
          type: finding[:severity].to_s,
          message: finding[:issue].to_s.empty? ? finding[:title].to_s : finding[:issue].to_s,
          detail: [
            finding[:recommendation],
            finding[:how_to_fix],
            ("evidence=#{Array(finding[:evidence]).join(' | ')}" if Array(finding[:evidence]).any?)
          ].compact.join("\n")
        }
      end
    end

    def junit_pass_placeholder(classname, name)
      {
        classname: classname,
        name: name,
        status: "pass",
        type: classname,
        message: name,
        detail: ""
      }
    end

    def junit_status_for_report(status)
      case status.to_s
      when "fail"
        "fail"
      when "warn"
        "warn"
      else
        "pass"
      end
    end

    def junit_status_for_severity(severity)
      case severity.to_s
      when "high", "medium"
        "fail"
      when "low"
        "warn"
      else
        "pass"
      end
    end

    def slugify(value)
      normalized = value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_+|_+\z/, "")
      normalized.empty? ? "unnamed_rule" : normalized
    end

    def xml_escape(value)
      value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;").gsub("'", "&apos;")
    end
  end
end
