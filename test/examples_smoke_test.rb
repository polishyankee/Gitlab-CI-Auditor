require_relative "test_helper"

class ExamplesSmokeTest < Minitest::Test
  def setup
    @example_cases = [
      {
        path: example_path("pipelines/compliant_service.gitlab-ci.yml"),
        policy_pack: "balanced",
        expected_grade: "A"
      },
      {
        path: example_path("pipelines/library_package.gitlab-ci.yml"),
        policy_pack: "library",
        expected_grade: "A"
      },
      {
        path: example_path("pipelines/legacy_monolith.gitlab-ci.yml"),
        policy_pack: "strict",
        expected_grade: "F"
      },
      {
        path: example_path("pipelines/snapshot_root.gitlab-ci.yml"),
        policy_pack: "balanced",
        expected_grade: "A"
      },
      {
        path: example_path("pipelines/samm_question_rich.gitlab-ci.yml"),
        policy_pack: "balanced",
        expected_grade: "A"
      },
      {
        path: example_path("pipelines/samm_question_gaps.gitlab-ci.yml"),
        policy_pack: "strict",
        expected_grade: "F"
      },
      {
        path: example_path("pipelines/upload_bundle_demo/.gitlab-ci.yml"),
        policy_pack: "balanced",
        expected_grade: "A"
      }
    ]
  end

  def test_examples_are_analyzable_with_expected_grades
    @example_cases.each do |example_case|
      loader = GitlabCiAuditor::PipelineLoader.new
      policy = GitlabCiAuditor::PolicyLoader.load(pack: example_case[:policy_pack])
      pipeline = loader.load(example_case[:path])
      report = GitlabCiAuditor::Analyzer.new(pipeline, policy).analyze

      assert_equal example_case[:expected_grade], report[:summary][:grade], example_case[:path]
    end
  end
end
