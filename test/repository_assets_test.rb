require_relative "test_helper"
require "yaml"

class RepositoryAssetsTest < Minitest::Test
  def test_dockerfile_uses_non_root_runtime_and_healthcheck
    dockerfile = File.read(File.join(GitlabCiAuditor.root_dir, "Dockerfile"))

    assert_includes dockerfile, "USER app"
    assert_includes dockerfile, "HEALTHCHECK"
    assert_includes dockerfile, 'ENTRYPOINT ["./bin/gitlab-ci-auditor"]'
    assert_includes dockerfile, 'CMD ["serve", "--host", "0.0.0.0", "--port", "4567"]'
  end

  def test_ci_workflow_targets_repository_root_and_smoke_tests_container
    workflow = YAML.load_file(File.join(GitlabCiAuditor.root_dir, ".github", "workflows", "ci.yml"))
    docker_build = workflow.fetch("jobs").fetch("docker-build")
    build_step = docker_build.fetch("steps").find { |step| step["uses"] == "docker/build-push-action@v7" }
    smoke_step = docker_build.fetch("steps").find { |step| step["name"] == "Smoke test CLI image" }

    refute_nil build_step
    refute_nil smoke_step
    assert_equal ".", build_step.fetch("with").fetch("context")
    assert_equal "./Dockerfile", build_step.fetch("with").fetch("file")
  end

  def test_release_workflow_publishes_example_reports
    workflow = YAML.load_file(File.join(GitlabCiAuditor.root_dir, ".github", "workflows", "release.yml"))
    release_job = workflow.fetch("jobs").fetch("release")
    release_step = release_job.fetch("steps").find { |step| step["uses"] == "softprops/action-gh-release@v2" }

    refute_nil release_step
    assert_includes release_step.fetch("with").fetch("files"), "examples/reports/*.html"
    assert_includes release_step.fetch("with").fetch("files"), "examples/reports/*.txt"
  end

  def test_readme_documents_docker_and_ghcr_usage
    readme = File.read(File.join(GitlabCiAuditor.root_dir, "README.md"))

    assert_includes readme, "## Docker"
    assert_includes readme, "## Quick Start"
    assert_includes readme, "## Why Teams Use It"
    assert_includes readme, "docs/assets/readme-preview.svg"
    assert_includes readme, "docker build --pull -t gitlab-ci-ssdlc-auditor ."
    assert_includes readme, "ghcr.io/polishyankee/gitlab-ci-auditor:latest"
    assert_includes readme, "./scripts/prepare_release.sh v0.3.0"
    assert_includes readme, "./scripts/flatten_pipeline.sh .gitlab-ci.yml --output flat.gitlab-ci.yml"
    assert_includes readme, "--format sarif"
    assert_includes readme, "--format junit"
  end

  def test_release_guide_and_prepare_script_exist
    release_guide = File.read(File.join(GitlabCiAuditor.root_dir, "RELEASE.md"))
    prepare_script = File.read(File.join(GitlabCiAuditor.root_dir, "scripts", "prepare_release.sh"))

    assert_includes release_guide, "## Release Checklist"
    assert_includes release_guide, "git push origin v0.3.0"
    assert_includes prepare_script, "docker build --pull"
    assert_includes prepare_script, "docker run --rm"
  end

  def test_flatten_pipeline_helper_script_exists
    helper_script = File.read(File.join(GitlabCiAuditor.root_dir, "scripts", "flatten_pipeline.sh"))

    assert_includes helper_script, "Usage: ./scripts/flatten_pipeline.sh ROOT_PIPELINE"
    assert_includes helper_script, "--output flat.gitlab-ci.yml"
    assert_includes helper_script, "ruby \"$cli_path\" flatten \"$@\""
  end

  def test_github_metadata_pack_and_preview_asset_exist
    metadata = File.read(File.join(GitlabCiAuditor.root_dir, "docs", "GITHUB_METADATA.md"))
    preview_svg = File.read(File.join(GitlabCiAuditor.root_dir, "docs", "assets", "readme-preview.svg"))

    assert_includes metadata, "## About Description"
    assert_includes metadata, "## Suggested Topics"
    assert_includes metadata, "## Social Preview"
    assert_includes preview_svg, "GitLab CI SSDLC Auditor"
    assert_includes preview_svg, "Pipeline Flow Graph"
  end

  def test_changelog_includes_current_release_target
    changelog = File.read(File.join(GitlabCiAuditor.root_dir, "CHANGELOG.md"))

    assert_includes changelog, "## v0.3.0"
    assert_includes changelog, "SARIF"
    assert_includes changelog, "JUnit"
  end
end
