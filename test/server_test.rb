require_relative "test_helper"
require "fileutils"
require "tmpdir"

class ServerTest < Minitest::Test
  RequestStub = Struct.new(:query)
  UploadStub = Struct.new(:filename, :body) do
    def to_s
      body
    end
  end

  def test_analyze_request_allows_nil_snapshot_file_in_gui_flow
    GitlabCiAuditor.require_server!

    server = GitlabCiAuditor::Server.new(
      host: "127.0.0.1",
      port: 4567
    )

    report = server.send(
      :analyze_request,
      RequestStub.new(
        {
          "pipeline_path" => fixture("good_pipeline.yml"),
          "policy_pack" => "balanced"
        }
      )
    )

    assert_equal "complete", report[:summary][:analysis_scope]
    assert report[:summary][:overall_score] >= 75
  rescue LoadError => error
    skip(error.message)
  end

  def test_analyze_request_supports_uploaded_pipeline_directory_bundle
    GitlabCiAuditor.require_server!

    server = GitlabCiAuditor::Server.new(
      host: "127.0.0.1",
      port: 4567
    )

    report = server.send(
      :analyze_request,
      RequestStub.new(
        {
          "pipeline_directory_files" => [
            UploadStub.new("uploaded-repo/.gitlab-ci.yml", nested_include_root_pipeline),
            UploadStub.new("uploaded-repo/.gitlab/ci/templates/prepare.yml", nested_prepare_template)
          ],
          "pipeline_directory_paths" => [
            "uploaded-repo/.gitlab-ci.yml",
            "uploaded-repo/.gitlab/ci/templates/prepare.yml"
          ],
          "pipeline_bundle_root" => ".gitlab-ci.yml",
          "policy_pack" => "balanced"
        }
      )
    )

    assert_equal "complete", report[:summary][:analysis_scope]
    assert_equal 1, report[:metadata][:resolved_local_includes].size
    assert report[:metadata][:resolved_local_includes].first.end_with?(".gitlab/ci/templates/prepare.yml")
  rescue LoadError => error
    skip(error.message)
  end

  def test_analyze_request_supports_root_upload_with_explicit_support_file_paths
    GitlabCiAuditor.require_server!

    server = GitlabCiAuditor::Server.new(
      host: "127.0.0.1",
      port: 4567
    )

    report = server.send(
      :analyze_request,
      RequestStub.new(
        {
          "pipeline_file" => UploadStub.new(".gitlab-ci.yml", nested_include_root_pipeline),
          "pipeline_support_files" => [
            UploadStub.new("prepare.yml", nested_prepare_template)
          ],
          "pipeline_support_paths" => [
            ".gitlab/ci/templates/prepare.yml"
          ],
          "policy_pack" => "balanced"
        }
      )
    )

    assert_equal "complete", report[:summary][:analysis_scope]
    assert_equal 1, report[:metadata][:resolved_local_includes].size
    assert report[:metadata][:resolved_local_includes].first.end_with?(".gitlab/ci/templates/prepare.yml")
  rescue LoadError => error
    skip(error.message)
  end

  def test_analyze_request_supports_uploaded_zip_bundle
    skip "zip command is unavailable" unless zip_available?

    GitlabCiAuditor.require_server!

    server = GitlabCiAuditor::Server.new(
      host: "127.0.0.1",
      port: 4567
    )

    report = server.send(
      :analyze_request,
      RequestStub.new(
        {
          "pipeline_archive" => uploaded_zip_bundle,
          "policy_pack" => "balanced"
        }
      )
    )

    assert_equal "complete", report[:summary][:analysis_scope]
    assert_equal 1, report[:metadata][:resolved_local_includes].size
    assert report[:metadata][:resolved_local_includes].first.end_with?(".gitlab/ci/templates/prepare.yml")
  rescue LoadError => error
    skip(error.message)
  end

  def test_analyze_request_supports_uploaded_zip_bundle_with_project_include_snapshot
    skip "zip command is unavailable" unless zip_available?

    GitlabCiAuditor.require_server!

    server = GitlabCiAuditor::Server.new(
      host: "127.0.0.1",
      port: 4567
    )

    report = server.send(
      :analyze_request,
      RequestStub.new(
        {
          "pipeline_archive" => uploaded_zip_bundle_with_project_include_snapshot,
          "policy_pack" => "balanced"
        }
      )
    )

    assert_equal "complete", report[:summary][:analysis_scope]
    assert_equal 1, report[:metadata][:resolved_local_includes].size
    assert report[:metadata][:resolved_local_includes].first.end_with?("templates/templates_dependency-policy.yml")
  rescue LoadError => error
    skip(error.message)
  end

  def test_analyze_request_rewrites_incomplete_upload_bundle_errors
    GitlabCiAuditor.require_server!

    server = GitlabCiAuditor::Server.new(
      host: "127.0.0.1",
      port: 4567
    )

    error = assert_raises(ArgumentError) do
      server.send(
        :analyze_request,
        RequestStub.new(
          {
            "pipeline_file" => UploadStub.new(".gitlab-ci.yml", nested_include_root_pipeline_without_tests),
            "policy_pack" => "balanced"
          }
        )
      )
    end

    assert_includes error.message, "extends unknown template"
    assert_includes error.message, "Selected root pipeline: .gitlab-ci.yml"
    assert_includes error.message, "YAML files detected in upload: .gitlab-ci.yml"
    assert_includes error.message, "upload the whole pipeline directory"
  rescue LoadError => error
    skip(error.message)
  end

  def test_analyze_request_surfaces_yaml_alias_diagnostics
    GitlabCiAuditor.require_server!

    server = GitlabCiAuditor::Server.new(
      host: "127.0.0.1",
      port: 4567
    )

    error = assert_raises(ArgumentError) do
      server.send(
        :analyze_request,
        RequestStub.new(
          {
            "pipeline_file" => UploadStub.new(".gitlab-ci.yml", root_pipeline_with_missing_alias),
            "policy_pack" => "balanced"
          }
        )
      )
    end

    assert_includes error.message, "Unknown YAML alias `dependency_policy_rules`"
    assert_includes error.message, "Selected root pipeline: .gitlab-ci.yml"
    assert_includes error.message, "Hidden templates detected: .prepare_dependency_policy_template"
    assert_includes error.message, "Alias references detected: dependency_policy_rules"
  rescue LoadError => error
    skip(error.message)
  end

  private

  def nested_include_root_pipeline
    <<~YAML
      include:
        - local: .gitlab/ci/templates/prepare.yml

      workflow:
        rules:
          - if: '$CI_COMMIT_BRANCH'

      stages:
        - prep
        - test

      prepare:
        extends: .prepare_template
        rules:
          - if: '$CI_COMMIT_BRANCH'

      unit_tests:
        stage: test
        script:
          - bundle exec rspec
        artifacts:
          paths:
            - coverage/jacoco.xml
        rules:
          - if: '$CI_COMMIT_BRANCH'
    YAML
  end

  def nested_include_root_pipeline_without_tests
    <<~YAML
      include:
        - local: .gitlab/ci/templates/prepare.yml

      workflow:
        rules:
          - if: '$CI_COMMIT_BRANCH'

      stages:
        - prep

      prepare:
        extends: .prepare_template
        rules:
          - if: '$CI_COMMIT_BRANCH'
    YAML
  end

  def nested_prepare_template
    <<~YAML
      .prepare_template:
        stage: prep
        script:
          - echo preparing
    YAML
  end

  def root_pipeline_with_missing_alias
    <<~YAML
      prepare_dependency_policy:
        extends: .prepare_dependency_policy_template
        rules: *dependency_policy_rules

      .prepare_dependency_policy_template:
        stage: prepare
        script:
          - echo preparing dependency policy
    YAML
  end

  def uploaded_zip_bundle
    archive_body = nil

    Dir.mktmpdir("gitlab-ci-auditor-zip") do |dir|
      bundle_root = File.join(dir, "bundle")
      FileUtils.mkdir_p(File.join(bundle_root, ".gitlab/ci/templates"))
      File.write(File.join(bundle_root, "root.gitlabci.yml"), nested_include_root_pipeline)
      File.write(File.join(bundle_root, ".gitlab/ci/templates/prepare.yml"), nested_prepare_template)

      archive_path = File.join(dir, "bundle.zip")
      Dir.chdir(dir) do
        success = system("zip", "-qr", archive_path, "bundle", out: File::NULL, err: File::NULL)
        raise "Failed to build test ZIP fixture" unless success
      end

      archive_body = File.binread(archive_path)
    end

    UploadStub.new("pipeline-bundle.zip", archive_body)
  end

  def uploaded_zip_bundle_with_project_include_snapshot
    archive_body = nil

    Dir.mktmpdir("gitlab-ci-auditor-project-zip") do |dir|
      bundle_root = File.join(dir, "bundle")
      FileUtils.mkdir_p(File.join(bundle_root, "templates"))
      File.write(File.join(bundle_root, "gitlab-ci.yml"), root_pipeline_with_project_include_snapshot)
      File.write(File.join(bundle_root, "templates/templates_dependency-policy.yml"), dependency_policy_template_snapshot)

      archive_path = File.join(dir, "bundle.zip")
      Dir.chdir(dir) do
        success = system("zip", "-qr", archive_path, "bundle", out: File::NULL, err: File::NULL)
        raise "Failed to build test ZIP fixture" unless success
      end

      archive_body = File.binread(archive_path)
    end

    UploadStub.new("pipeline-project-bundle.zip", archive_body)
  end

  def root_pipeline_with_project_include_snapshot
    <<~YAML
      include:
        - project: "assecoars/gitlab-ci"
          ref: main
          file: "templates/templates_dependency-policy.yml"

      prepare_dependency_policy:
        extends: .prepare_dependency_policy_template
        rules:
          - when: always
    YAML
  end

  def dependency_policy_template_snapshot
    <<~YAML
      .prepare_dependency_policy_template:
        stage: prepare
        script:
          - echo preparing dependency policy
    YAML
  end

  def zip_available?
    system("zip", "-v", out: File::NULL, err: File::NULL)
  end
end
