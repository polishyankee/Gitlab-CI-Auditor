require_relative "test_helper"
require "fileutils"
require "tmpdir"

class CliTest < Minitest::Test
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
