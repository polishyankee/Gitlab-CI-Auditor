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

  def test_analyze_request_supports_pasted_pipeline_yaml
    GitlabCiAuditor.require_server!

    server = GitlabCiAuditor::Server.new(
      host: "127.0.0.1",
      port: 4567
    )

    report = server.send(
      :analyze_request,
      RequestStub.new(
        {
          "pipeline_text" => pasted_single_file_pipeline,
          "pipeline_text_filename" => ".gitlab-ci.yml",
          "policy_pack" => "balanced"
        }
      )
    )

    assert_equal "complete", report[:summary][:analysis_scope]
    assert_equal ".gitlab-ci.yml", File.basename(report[:pipeline_path])
    assert_equal "pass", report.dig(:lint, :status)
    assert report[:graph][:nodes].any?
    assert report[:recommendations].any?
  rescue LoadError => error
    skip(error.message)
  end

  def test_analyze_request_supports_pasted_pipeline_with_support_files
    GitlabCiAuditor.require_server!

    server = GitlabCiAuditor::Server.new(
      host: "127.0.0.1",
      port: 4567
    )

    report = server.send(
      :analyze_request,
      RequestStub.new(
        {
          "pipeline_text" => nested_include_root_pipeline,
          "pipeline_text_filename" => ".gitlab-ci.yml",
          "pipeline_text_support_paths" => [
            ".gitlab/ci/templates/prepare.yml"
          ],
          "pipeline_text_support_contents" => [
            nested_prepare_template
          ],
          "policy_pack" => "balanced"
        }
      )
    )

    assert_equal "complete", report[:summary][:analysis_scope]
    assert_equal 1, report[:metadata][:resolved_local_includes].size
    assert report[:metadata][:resolved_local_includes].first.end_with?(".gitlab/ci/templates/prepare.yml")
    assert_equal "pass", report.dig(:lint, :status)
  rescue LoadError => error
    skip(error.message)
  end

  def test_analyze_request_rejects_pasted_shell_script_instead_of_yaml
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
            "pipeline_text" => "#!/usr/bin/env sh\nset -eu\n",
            "pipeline_text_filename" => ".gitlab-ci.yml",
            "policy_pack" => "balanced"
          }
        )
      )
    end

    assert_includes error.message, "looks like a shell script"
    assert_includes error.message, "gitlab-ci-auditor flatten"
  rescue LoadError => error
    skip(error.message)
  end

  def test_analyze_request_supports_context_manifest_and_history_store
    GitlabCiAuditor.require_server!

    Dir.mktmpdir("gitlab-ci-auditor-server-history") do |dir|
      history_path = File.join(dir, "history.json")
      server = GitlabCiAuditor::Server.new(
        host: "127.0.0.1",
        port: 4567
      )

      report = server.send(
        :analyze_request,
        RequestStub.new(
          {
            "pipeline_path" => fixture("context_root.yml"),
            "context_file_path" => fixture("context_manifest.json"),
            "history_file_path" => history_path,
            "policy_pack" => "balanced"
          }
        )
      )

      assert_equal "complete", report[:summary][:analysis_scope]
      assert_equal 2, report[:summary][:total_pipeline_files]
      assert_equal true, report.dig(:history, :enabled)
      assert_equal fixture("context_manifest.json"), report.dig(:metadata, :context_manifest)
      assert File.exist?(history_path)
    end
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

  def test_analyze_request_supports_root_upload_with_flattened_project_include_snapshot_name
    GitlabCiAuditor.require_server!

    server = GitlabCiAuditor::Server.new(
      host: "127.0.0.1",
      port: 4567
    )

    report = server.send(
      :analyze_request,
      RequestStub.new(
        {
          "pipeline_file" => UploadStub.new(".gitlab-ci.yml", root_pipeline_with_project_include_snapshot),
          "pipeline_support_files" => [
            UploadStub.new("templates_dependency-policy.yml", dependency_policy_template_snapshot)
          ],
          "policy_pack" => "balanced"
        }
      )
    )

    assert_equal "complete", report[:summary][:analysis_scope]
    assert_equal 1, report[:metadata][:resolved_local_includes].size
    assert report[:metadata][:resolved_local_includes].first.end_with?("templates_dependency-policy.yml")
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

  def pasted_single_file_pipeline
    <<~YAML
      workflow:
        rules:
          - if: '$CI_COMMIT_BRANCH'

      stages:
        - build
        - security
        - deploy

      build_and_test:
        stage: build
        script:
          - mvn -B clean verify cyclonedx:makeAggregateBom
        artifacts:
          paths:
            - target/site/jacoco/jacoco.xml
            - target/bom.cyclonedx.xml

      sast:
        stage: security
        script:
          - semgrep --config auto .

      dependency_scan:
        stage: security
        script:
          - trivy fs --exit-code 1 .

      secret_detection:
        stage: security
        script:
          - gitleaks detect --no-git --exit-code 1 --report-format json --report-path gl-secret-detection-report.json .
        artifacts:
          paths:
            - gl-secret-detection-report.json

      iac_policy:
        stage: security
        script:
          - trivy config --exit-code 1 k8s/
        artifacts:
          paths:
            - trivy-config-report.json

      deploy_test:
        stage: deploy
        environment:
          name: test
        script:
          - kubectl apply -f k8s/test.yaml

      dast:
        stage: deploy
        needs:
          - deploy_test
        script:
          - zap-baseline.py -t https://test.example.internal -J gl-dast-report.json
        artifacts:
          paths:
            - gl-dast-report.json
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
        - project: "example-org/ci-templates"
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
