require_relative "test_helper"

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
    assert_includes html, "blue dashed: multi-project context link"
    assert_includes html, "OWASP SAMM rules:"
    assert_includes html, "Upstream question mapping:"
    assert_includes html, "Observability:"
    assert_includes html, "grid-template-columns: 1fr"
    assert_includes html, "benchmark-link"
    assert_includes html, "pipeline_short_label"
    assert_includes html, "minmax(320px, 1fr)"
    assert_includes html, "edge-context"
  end
end
