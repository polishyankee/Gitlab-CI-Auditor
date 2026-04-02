require_relative "test_helper"

class ContextLoaderTest < Minitest::Test
  def test_context_manifest_links_multiple_projects_into_one_graph
    loader = GitlabCiAuditor::ContextLoader.new(context_file: fixture("context_manifest.json"))
    pipeline = loader.load(fixture("context_root.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    assert_equal 2, report[:summary][:total_pipeline_files]
    assert_equal "complete", report[:summary][:analysis_scope]
    assert_equal fixture("context_manifest.json"), report.dig(:metadata, :context_manifest)
    assert_includes report.dig(:metadata, :context_projects), "application"
    assert_includes report.dig(:metadata, :context_projects), "delivery"
    assert_equal "pass", report[:categories].find { |category| category[:key] == "sbom" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "secret_detection" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "iac" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "dast" }[:status]
    assert report[:graph][:edges].any? { |edge| edge[:type] == "context" }
  end
end
