require_relative "test_helper"

class RuleEvaluatorTest < Minitest::Test
  def setup
    @loader = GitlabCiAuditor::PipelineLoader.new
  end

  def test_changes_rules_match_only_relevant_changed_files
    pipeline = @loader.load(fixture("changes_rules.yml"))
    evaluator = GitlabCiAuditor::RuleEvaluator.new(pipeline)
    app_scenario = {
      source: "push",
      branch: "main",
      tag: nil,
      changed_files: ["src/app.rb"],
      variables: {
        "CI_PIPELINE_SOURCE" => "push",
        "CI_COMMIT_BRANCH" => "main",
        "CI_COMMIT_TAG" => nil,
        "CI_COMMIT_REF_NAME" => "main",
        "CI_DEFAULT_BRANCH" => "main"
      }
    }

    app_result = evaluator.evaluate_job("app_quality", pipeline.jobs.fetch("app_quality"), app_scenario)
    docs_result = evaluator.evaluate_job("docs_lint", pipeline.jobs.fetch("docs_lint"), app_scenario)

    assert_equal true, app_result[:included]
    assert_equal false, docs_result[:included]
  end

  def test_only_except_patterns_filter_ref_types
    pipeline = GitlabCiAuditor::PipelineLoader::Pipeline.new(
      path: fixture("good_pipeline.yml"),
      base_dir: File.dirname(fixture("good_pipeline.yml")),
      raw_config: {},
      jobs: {},
      templates: {},
      stages: [],
      variables: {},
      workflow: {},
      global_before_script: [],
      global_after_script: [],
      include_metadata: {},
      downstream_references: [],
      warnings: []
    )
    evaluator = GitlabCiAuditor::RuleEvaluator.new(pipeline)
    job = { "only" => ["branches"], "except" => ["main"] }

    included = evaluator.send(
      :only_except_match?,
      job,
      { source: "push", branch: "feature/login", tag: nil }
    )
    excluded = evaluator.send(
      :only_except_match?,
      job,
      { source: "push", branch: "main", tag: nil }
    )

    assert_equal true, included
    assert_equal false, excluded
  end
end
