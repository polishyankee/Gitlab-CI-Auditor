require_relative "test_helper"
require "fileutils"
require "tmpdir"

class CliTest < Minitest::Test
  def test_flatten_writes_single_yaml_output_file
    Dir.mktmpdir("gitlab-ci-cli-flatten") do |dir|
      FileUtils.mkdir_p(File.join(dir, ".gitlab", "ci", "templates"))

      root_path = File.join(dir, ".gitlab-ci.yml")
      output_path = File.join(dir, "flat.gitlab-ci.yml")

      File.write(
        root_path,
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

      stdout, = capture_io do
        GitlabCiAuditor::CLI.new.send(:flatten, [root_path, "--output", output_path])
      end

      assert_includes stdout, "Flattened pipeline written"
      flattened_content = File.read(output_path)
      refute_includes flattened_content, "\ninclude:"
      parsed = YAML.safe_load(flattened_content.lines.reject { |line| line.start_with?("#") }.join, aliases: true)
      assert_equal "prepare", parsed.fetch(".prepare_template").fetch("stage")
      assert_equal ".prepare_template", parsed.fetch("prepare_job").fetch("extends")
    end
  end

  def test_scan_enriches_unknown_template_errors_with_workspace_diagnostics
    Dir.mktmpdir("gitlab-ci-cli-diagnostics") do |dir|
      File.write(
        File.join(dir, "root.gitlab-ci.yml"),
        <<~YAML
          include:
            - project: "example-org/ci-templates"
              ref: main
              file: "templates/templates_dependency-policy.yml"

          build:
            extends: .maven_build_with_policy_template
        YAML
      )

      File.write(
        File.join(dir, "templates_dependency-policy.yml"),
        <<~YAML
          .maven_build_with_policy_template:
            extends: .maven_build_template
            script:
              - echo build with policy
        YAML
      )

      File.write(
        File.join(dir, "templates_maven.yml"),
        <<~YAML
          .maven_build_template:
            stage: build
            script:
              - echo base maven build
        YAML
      )

      error = assert_raises(ArgumentError) do
        GitlabCiAuditor::CLI.new.send(:scan, [File.join(dir, "root.gitlab-ci.yml")])
      end

      assert_includes error.message, "extends unknown template .maven_build_template"
      assert_includes error.message, "Template `.maven_build_template` was found in workspace file(s): templates_maven.yml"
      assert_includes error.message, "Selected root pipeline: root.gitlab-ci.yml"
      assert_includes error.message, "YAML files detected in workspace:"
      assert_includes error.message, "Hidden templates detected in workspace:"
    end
  end
end
