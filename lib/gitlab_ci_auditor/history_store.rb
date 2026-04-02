module GitlabCiAuditor
  class HistoryStore
    DEFAULT_WINDOW = 20

    def initialize(path)
      @path = File.expand_path(path)
    end

    def attach(report)
      append(report)
      report[:history] = dashboard_for(report)
      report
    end

    def dashboard_for(report, window: DEFAULT_WINDOW)
      records = matching_records(report).last(window)
      latest = records.last
      previous = records[-2]

      {
        enabled: true,
        path: @path,
        total_runs: records.size,
        score_delta: previous ? latest["overall_score"].to_i - previous["overall_score"].to_i : 0,
        previous_score: previous && previous["overall_score"],
        recent_runs: records.map do |record|
          {
            generated_at: record["generated_at"],
            overall_score: record["overall_score"],
            max_score: record["max_score"],
            grade: record["grade"],
            status: record["status"],
            policy_pack_name: record["policy_pack_name"]
          }
        end,
        category_deltas: category_deltas(latest, previous),
        benchmark_deltas: benchmark_deltas(latest, previous)
      }
    end

    private

    def append(report)
      payload = load_payload
      payload["records"] << record_from_report(report)
      persist_payload(payload)
    end

    def matching_records(report)
      load_payload.fetch("records", []).select do |record|
        record["pipeline_path"] == report[:pipeline_path] &&
          record["policy_pack_name"] == report.dig(:summary, :policy_pack_name)
      end.sort_by { |record| record["generated_at"].to_s }
    end

    def category_deltas(latest, previous)
      latest_categories = latest ? latest.fetch("categories", {}) : {}
      previous_categories = previous ? previous.fetch("categories", {}) : {}

      latest_categories.map do |key, current|
        older = previous_categories[key] || {}
        {
          key: key,
          title: current["title"],
          current_score: current["score"].to_i,
          max_score: current["max_score"].to_i,
          status: current["status"],
          delta: current["score"].to_i - older.fetch("score", current["score"]).to_i
        }
      end
    end

    def benchmark_deltas(latest, previous)
      latest_benchmarks = latest ? latest.fetch("benchmarks", {}) : {}
      previous_benchmarks = previous ? previous.fetch("benchmarks", {}) : {}

      latest_benchmarks.map do |key, current|
        older = previous_benchmarks[key] || {}
        {
          key: key,
          title: current["title"],
          current_score: current["alignment_score"].to_i,
          status: current["status"],
          delta: current["alignment_score"].to_i - older.fetch("alignment_score", current["alignment_score"]).to_i
        }
      end
    end

    def load_payload
      return { "records" => [] } unless File.exist?(@path)

      JSON.parse(File.read(@path))
    rescue JSON::ParserError => error
      raise ArgumentError, "Failed to parse history store #{@path}: #{error.message}"
    end

    def persist_payload(payload)
      FileUtils.mkdir_p(File.dirname(@path))
      File.write(@path, JSON.pretty_generate(payload))
    end

    def record_from_report(report)
      {
        "generated_at" => report[:generated_at],
        "pipeline_path" => report[:pipeline_path],
        "policy_pack_name" => report.dig(:summary, :policy_pack_name),
        "overall_score" => report.dig(:summary, :overall_score),
        "max_score" => report.dig(:summary, :max_score),
        "grade" => report.dig(:summary, :grade),
        "status" => report.dig(:summary, :status),
        "categories" => report.fetch(:categories, {}).each_with_object({}) do |category, memo|
          memo[category[:key].to_s] = {
            "title" => category[:title],
            "score" => category[:score],
            "max_score" => category[:max_score],
            "status" => category[:status]
          }
        end,
        "benchmarks" => report.fetch(:benchmarks, {}).each_with_object({}) do |(key, benchmark), memo|
          practices = Array(benchmark[:practices])
          memo[key.to_s] = {
            "title" => benchmark[:framework],
            "alignment_score" => practices.empty? ? 0 : (practices.sum { |practice| practice[:alignment_score].to_i } / practices.size),
            "status" => practices.any? { |practice| practice[:status] == "fail" } ? "fail" : (practices.any? { |practice| practice[:status] == "warn" } ? "warn" : "pass")
          }
        end
      }
    end
  end
end
