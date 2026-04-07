require_relative "test_helper"
require "rexml/document"

class ReportRendererTest < Minitest::Test
  def setup
    loader = GitlabCiAuditor::PipelineLoader.new
    pipeline = loader.load(fixture("good_pipeline.yml"))
    @report = GitlabCiAuditor::Analyzer.new(pipeline).analyze
    @renderer = GitlabCiAuditor::ReportRenderer.new(@report)
  end

  def test_render_text_includes_policy_pack_and_scope
    text = @renderer.render_text

    assert_includes text, "Lint:"
    assert_includes text, "Policy Pack:"
    assert_includes text, "Scope:"
    assert_includes text, "Categories:"
    assert_includes text, "OWASP SAMM v2:"
    assert_includes text, "observed Analysis Scope:"
    assert_includes text, "rule ["
  end

  def test_render_json_bundle_contains_report_and_exporter_meta
    payload = JSON.parse(@renderer.render_json_bundle)

    assert_equal "json_bundle", payload.dig("meta", "format")
    assert_equal @report[:summary][:overall_score], payload.dig("report", "summary", "overall_score")
    assert_includes payload.dig("exports", "text"), "GitLab CI SSDLC Audit"
  end

  def test_render_sarif_emits_machine_readable_findings
    report = GitlabCiAuditor::Analyzer.new(
      GitlabCiAuditor::PipelineLoader.new.load(example_path("pipelines/legacy_monolith.gitlab-ci.yml"))
    ).analyze

    payload = JSON.parse(GitlabCiAuditor::ReportRenderer.new(report).render_sarif)
    run = payload.fetch("runs").first

    assert_equal "2.1.0", payload.fetch("version")
    assert_equal "GitLab CI SSDLC Auditor", run.dig("tool", "driver", "name")
    assert_equal report[:pipeline_path], run.dig("properties", "pipeline_path")
    assert_operator run.fetch("results").size, :>, 0
    assert run.fetch("results").any? { |result| result.fetch("ruleId").start_with?("ssdlc/") || result.fetch("ruleId").start_with?("security/") || result.fetch("ruleId").start_with?("lint/") }
  end

  def test_render_junit_outputs_parseable_testsuites
    report = GitlabCiAuditor::Analyzer.new(
      GitlabCiAuditor::PipelineLoader.new.load(example_path("pipelines/legacy_monolith.gitlab-ci.yml"))
    ).analyze

    xml = GitlabCiAuditor::ReportRenderer.new(report).render_junit
    document = REXML::Document.new(xml)
    suites = document.root.elements.to_a("testsuite")
    suite_names = suites.map { |suite| suite.attributes["name"] }

    assert_equal "testsuites", document.root.name
    assert_operator document.root.attributes["tests"].to_i, :>, 0
    assert_includes suite_names, "summary"
    assert_includes suite_names, "categories"
    assert_includes suite_names, "ssdlc"
    assert_includes suite_names, "security"
  end

  def test_render_html_includes_full_width_graph_panel_markup
    html = @renderer.render_html

    assert_includes html, 'data-tab="lint"'
    assert_includes html, 'data-tab="trends"'
    assert_includes html, 'class="section tab-panel graph-panel"'
    assert_includes html, 'class="section tab-panel benchmark-panel"'
    assert_includes html, 'data-tab="benchmark"'
    assert_includes html, "OWASP SAMM v2 Benchmark"
    assert_includes html, "Historical Trend Dashboard"
    assert_includes html, "Lint and Best Practices"
    assert_includes html, "Analysis Scope"
    assert_includes html, "Image scan families: none detected"
    assert_includes html, "OWASP SAMM rules:"
    assert_includes html, "Upstream question mapping:"
    assert_includes html, "Observability:"
    assert_includes html, "grid-template-columns: 1fr"
    assert_includes html, "benchmark-link"
    assert_includes html, "pipeline_short_label"
    assert_includes html, "minmax(320px, 1fr)"
    assert_includes html, "edge-context"
    assert_includes html, "Critical Path"
    assert_includes html, "Gate overlays"
    assert_includes html, "edge-critical"
  end

  def test_render_html_includes_diff_tab_when_diff_data_exists
    baseline_pipeline = GitlabCiAuditor::PipelineLoader.new.load(example_path("pipelines/legacy_monolith.gitlab-ci.yml"))
    baseline_report = GitlabCiAuditor::Analyzer.new(baseline_pipeline).analyze
    @report[:diff] = GitlabCiAuditor::ReportDiff.build(@report, baseline_report)

    html = GitlabCiAuditor::ReportRenderer.new(@report).render_html

    assert_includes html, 'data-tab="diff"'
    assert_includes html, "Pipeline Revision Diff"
    assert_includes html, "Diff Summary"
    assert_includes html, "Category Changes"
  end
end
