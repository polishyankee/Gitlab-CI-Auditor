require_relative "test_helper"

class PipelineLoaderTest < Minitest::Test
  def test_auto_detects_snapshot_manifest_in_examples_directory
    loader = GitlabCiAuditor::PipelineLoader.new
    pipeline = loader.load(example_path("pipelines/snapshot_root.gitlab-ci.yml"))

    assert_equal 1, pipeline.downstream_references.size
    assert pipeline.downstream_references.first.pipeline
    assert_equal "external_project_snapshot", pipeline.downstream_references.first.kind
  end

  def test_missing_snapshot_manifest_path_raises_error
    loader = GitlabCiAuditor::PipelineLoader.new(snapshot_file: example_path("pipelines/missing.json"))

    error = assert_raises(ArgumentError) do
      loader.load(fixture("external_project_root.yml"))
    end

    assert_includes error.message, "Snapshot manifest not found"
  end
end
