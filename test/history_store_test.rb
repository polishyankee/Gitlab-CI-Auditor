require_relative "test_helper"
require "tmpdir"
require "time"

class HistoryStoreTest < Minitest::Test
  def test_history_store_appends_runs_and_returns_trend_summary
    Dir.mktmpdir("gitlab-ci-auditor-history") do |dir|
      history_path = File.join(dir, "history.json")
      loader = GitlabCiAuditor::PipelineLoader.new
      strong_report = GitlabCiAuditor::Analyzer.new(loader.load(fixture("good_pipeline.yml"))).analyze
      weak_report = Marshal.load(Marshal.dump(strong_report))
      weak_report[:generated_at] = (Time.parse(strong_report[:generated_at]) + 60).utc.iso8601
      weak_report[:summary][:overall_score] = strong_report[:summary][:overall_score] - 20
      weak_report[:summary][:grade] = "B"
      weak_report[:summary][:status] = "acceptable"
      weak_report[:categories].first[:score] = [weak_report[:categories].first[:score] - 5, 0].max
      store = GitlabCiAuditor::HistoryStore.new(history_path)

      first = store.attach(strong_report)
      second = store.attach(weak_report)

      assert_equal true, first.dig(:history, :enabled)
      assert_equal 1, first.dig(:history, :total_runs)
      assert_equal 2, second.dig(:history, :total_runs)
      assert_operator second.dig(:history, :score_delta), :<, 0
      assert_equal strong_report[:summary][:overall_score], second.dig(:history, :previous_score)
      assert File.exist?(history_path)
    end
  end
end
