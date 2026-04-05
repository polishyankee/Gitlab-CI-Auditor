require_relative "test_helper"

class CliDiffTest < Minitest::Test
  def test_scan_supports_compare_to_mode
    output, = capture_io do
      GitlabCiAuditor::CLI.start(
        [
          "scan",
          fixture("good_pipeline.yml"),
          "--compare-to",
          example_path("pipelines/legacy_monolith.gitlab-ci.yml")
        ]
      )
    end

    assert_includes output, "Diff vs:"
    assert_includes output, "Diff Summary:"
    assert_includes output, "Score Delta:"
  end
end
