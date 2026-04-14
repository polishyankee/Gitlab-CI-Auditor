require_relative "test_helper"
require "fileutils"
require "tmpdir"

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

  def test_resolves_include_project_snapshots_from_local_bundle_files
    Dir.mktmpdir("gitlab-ci-project-include") do |dir|
      FileUtils.mkdir_p(File.join(dir, "templates"))

      File.write(
        File.join(dir, "gitlab-ci.yml"),
        <<~YAML
          include:
            - project: "example-org/ci-templates"
              ref: main
              file: "templates/templates_dependency-policy.yml"

          prepare_dependency_policy:
            extends: .prepare_dependency_policy_template
            rules:
              - when: always
        YAML
      )

      File.write(
        File.join(dir, "templates", "templates_dependency-policy.yml"),
        <<~YAML
          .prepare_dependency_policy_template:
            stage: prepare
            script:
              - echo preparing dependency policy
        YAML
      )

      loader = GitlabCiAuditor::PipelineLoader.new
      pipeline = loader.load(File.join(dir, "gitlab-ci.yml"))

      assert_includes pipeline.jobs.keys, "prepare_dependency_policy"
      assert_includes pipeline.templates.keys, ".prepare_dependency_policy_template"
      assert_equal "prepare", pipeline.jobs["prepare_dependency_policy"]["stage"]
      assert_equal 1, pipeline.include_metadata[:resolved_project_includes].size
      assert_equal "templates/templates_dependency-policy.yml", pipeline.include_metadata[:resolved_project_includes].first["file"]
    end
  end

  def test_resolves_include_project_snapshots_from_flattened_uploaded_filenames
    Dir.mktmpdir("gitlab-ci-project-include-flat") do |dir|
      File.write(
        File.join(dir, ".gitlab-ci.yml"),
        <<~YAML
          include:
            - project: "example-org/ci-templates"
              ref: main
              file: "templates/templates_dependency-policy.yml"

          prepare_dependency_policy:
            extends: .prepare_dependency_policy_template
            rules:
              - when: always
        YAML
      )

      File.write(
        File.join(dir, "templates_dependency-policy.yml"),
        <<~YAML
          .prepare_dependency_policy_template:
            stage: prepare
            script:
              - echo preparing dependency policy
        YAML
      )

      loader = GitlabCiAuditor::PipelineLoader.new
      pipeline = loader.load(File.join(dir, ".gitlab-ci.yml"))

      assert_includes pipeline.jobs.keys, "prepare_dependency_policy"
      assert_includes pipeline.templates.keys, ".prepare_dependency_policy_template"
      assert_equal "prepare", pipeline.jobs["prepare_dependency_policy"]["stage"]
      assert_equal 1, pipeline.include_metadata[:resolved_project_includes].size
      assert pipeline.include_metadata[:resolved_project_includes].first["path"].end_with?("templates_dependency-policy.yml")
    end
  end

  def test_flatten_produces_single_audit_friendly_yaml_file
    Dir.mktmpdir("gitlab-ci-flatten") do |dir|
      FileUtils.mkdir_p(File.join(dir, ".gitlab", "ci", "templates"))

      File.write(
        File.join(dir, ".gitlab-ci.yml"),
        <<~YAML
          include:
            - local: ".gitlab/ci/templates/prepare.yml"

          prepare_job:
            extends: .prepare_template
        YAML
      )

      File.write(
        File.join(dir, ".gitlab", "ci", "templates", "prepare.yml"),
        <<~YAML
          .prepare_template:
            stage: prepare
            script:
              - echo prepare
        YAML
      )

      flattened = GitlabCiAuditor::PipelineLoader.new.flatten(File.join(dir, ".gitlab-ci.yml"))

      assert_includes flattened.yaml, "Flattened audit-friendly pipeline"
      refute_includes flattened.yaml, "\ninclude:"

      parsed = YAML.safe_load(flattened.yaml.lines.reject { |line| line.start_with?("#") }.join, aliases: true)
      assert_equal "prepare", parsed.fetch(".prepare_template").fetch("stage")
      assert_equal ".prepare_template", parsed.fetch("prepare_job").fetch("extends")
    end
  end
end
