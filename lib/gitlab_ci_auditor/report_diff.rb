module GitlabCiAuditor
  class ReportDiff
    FINDING_SECTIONS = {
      ssdlc: :ssdlc_findings,
      security: :security_findings
    }.freeze

    def self.build(current_report, baseline_report)
      new(current_report, baseline_report).build
    end

    def initialize(current_report, baseline_report)
      @current_report = current_report
      @baseline_report = baseline_report
    end

    def build
      {
        enabled: true,
        baseline: report_snapshot(@baseline_report),
        current: report_snapshot(@current_report),
        score_delta: @current_report.dig(:summary, :overall_score).to_i - @baseline_report.dig(:summary, :overall_score).to_i,
        max_score_delta: @current_report.dig(:summary, :max_score).to_i - @baseline_report.dig(:summary, :max_score).to_i,
        grade_changed: @current_report.dig(:summary, :grade) != @baseline_report.dig(:summary, :grade),
        status_changed: @current_report.dig(:summary, :status) != @baseline_report.dig(:summary, :status),
        category_deltas: category_deltas,
        finding_deltas: finding_deltas,
        highlights: highlights
      }
    end

    private

    def report_snapshot(report)
      {
        pipeline_path: report[:pipeline_path],
        generated_at: report[:generated_at],
        score: report.dig(:summary, :overall_score),
        max_score: report.dig(:summary, :max_score),
        grade: report.dig(:summary, :grade),
        status: report.dig(:summary, :status),
        policy_pack_name: report.dig(:summary, :policy_pack_name),
        policy_pack_label: report.dig(:summary, :policy_pack_label),
        analysis_scope: report.dig(:summary, :analysis_scope)
      }
    end

    def category_deltas
      baseline_by_key = Array(@baseline_report[:categories]).each_with_object({}) do |category, memo|
        memo[category[:key]] = category
      end

      Array(@current_report[:categories]).map do |category|
        baseline = baseline_by_key[category[:key]] || {}
        {
          key: category[:key],
          title: category[:title],
          current_score: category[:score].to_i,
          baseline_score: baseline.fetch(:score, 0).to_i,
          current_max_score: category[:max_score].to_i,
          baseline_max_score: baseline.fetch(:max_score, 0).to_i,
          delta: category[:score].to_i - baseline.fetch(:score, 0).to_i,
          current_status: category[:status],
          baseline_status: baseline[:status],
          summary: category[:summary]
        }
      end.sort_by { |delta| [-delta[:delta].abs, delta[:title].to_s] }
    end

    def finding_deltas
      FINDING_SECTIONS.each_with_object({}) do |(section_key, report_key), memo|
        current = index_findings(@current_report[report_key])
        baseline = index_findings(@baseline_report[report_key])

        memo[section_key] = {
          added: (current.keys - baseline.keys).sort.map { |title| serialize_finding(title, current[title]) },
          resolved: (baseline.keys - current.keys).sort.map { |title| serialize_finding(title, baseline[title]) },
          severity_changed: (current.keys & baseline.keys).sort.map do |title|
            next if current[title][:severity] == baseline[title][:severity]

            {
              title: title,
              baseline_severity: baseline[title][:severity],
              current_severity: current[title][:severity],
              baseline_issue: baseline[title][:issue],
              current_issue: current[title][:issue]
            }
          end.compact
        }
      end
    end

    def index_findings(findings)
      Array(findings).each_with_object({}) do |finding, memo|
        memo[finding[:title]] = finding
      end
    end

    def serialize_finding(title, finding)
      {
        title: title,
        severity: finding[:severity],
        issue: finding[:issue]
      }
    end

    def highlights
      items = []
      score_delta = @current_report.dig(:summary, :overall_score).to_i - @baseline_report.dig(:summary, :overall_score).to_i

      if score_delta.positive?
        items << "Overall score improved by #{score_delta} point#{score_delta == 1 ? '' : 's'}."
      elsif score_delta.negative?
        items << "Overall score regressed by #{score_delta.abs} point#{score_delta.abs == 1 ? '' : 's'}."
      else
        items << "Overall score stayed unchanged."
      end

      improvements = category_deltas.select { |delta| delta[:delta].positive? }.first(3)
      regressions = category_deltas.select { |delta| delta[:delta].negative? }.first(3)
      items << "Improved categories: #{improvements.map { |delta| "#{delta[:title]} (+#{delta[:delta]})" }.join(', ')}." if improvements.any?
      items << "Regressed categories: #{regressions.map { |delta| "#{delta[:title]} (#{delta[:delta]})" }.join(', ')}." if regressions.any?

      FINDING_SECTIONS.each_key do |section_key|
        deltas = finding_deltas[section_key]
        items << "#{section_key.to_s.upcase} findings added: #{deltas[:added].size}." if deltas[:added].any?
        items << "#{section_key.to_s.upcase} findings resolved: #{deltas[:resolved].size}." if deltas[:resolved].any?
      end

      items
    end
  end
end
