require "minitest/autorun"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "gitlab_ci_auditor"

class GitlabCiAuditorTest < Minitest::Test
  def setup
    @loader = GitlabCiAuditor::PipelineLoader.new
  end

  def test_loader_resolves_local_include_and_extends
    pipeline = @loader.load(fixture("good_pipeline.yml"))

    assert pipeline.jobs.key?("unit_tests")
    assert pipeline.jobs.key?("sast")
    assert_equal ["bundle exec rspec"], pipeline.jobs["unit_tests"]["script"]
    assert_equal 1, pipeline.include_metadata[:resolved_local_includes].size
  end

  def test_good_pipeline_scores_as_compliant
    pipeline = @loader.load(fixture("good_pipeline.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    assert report[:summary][:overall_score] >= 75
    assert report[:categories].find { |category| category[:key] == "unit_tests" }[:score] >= 10
    assert_equal "pass", report[:categories].find { |category| category[:key] == "coverage_report" }[:status]
    assert report[:scenarios].any? { |scenario| scenario[:status] == "pass" }
  end

  def test_repository_pipeline_reports_missing_ssdlc_controls
    pipeline = @loader.load(repo_pipeline)
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    unit_tests = report[:categories].find { |category| category[:key] == "unit_tests" }
    coverage_report = report[:categories].find { |category| category[:key] == "coverage_report" }
    sast = report[:categories].find { |category| category[:key] == "sast" }
    scan = report[:categories].find { |category| category[:key] == "scan" }
    deploy_test = report[:categories].find { |category| category[:key] == "deploy_test" }

    assert_equal "fail", unit_tests[:status]
    assert_equal "fail", coverage_report[:status]
    assert_equal "fail", sast[:status]
    assert_equal "fail", scan[:status]
    assert_equal "fail", deploy_test[:status]
    assert report[:recommendations].any? { |item| item.include?("workflow:rules") }
  end

  def test_build_jobs_can_satisfy_unit_test_control_without_dedicated_test_job
    pipeline = @loader.load(fixture("build_embedded_tests.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    unit_tests = report[:categories].find { |category| category[:key] == "unit_tests" }
    coverage_report = report[:categories].find { |category| category[:key] == "coverage_report" }
    scenario = report[:scenarios].find { |item| item[:status] != "skipped" }
    classified_jobs = scenario[:jobs].select { |job| job[:classifications].include?("unit_tests") }.map { |job| job[:name] }
    coverage_jobs = scenario[:jobs].select { |job| job[:classifications].include?("coverage_report") }.map { |job| job[:name] }

    assert_equal "pass", unit_tests[:status]
    assert_equal "pass", coverage_report[:status]
    assert_includes classified_jobs, "maven_build"
    assert_includes classified_jobs, "gradle_build"
    assert_includes classified_jobs, "jacoco_artifacts_build"
    assert_equal ["jacoco_artifacts_build"], coverage_jobs
    refute_includes classified_jobs, "skipped_tests_build"
  end

  def test_downstream_child_pipeline_is_scanned_as_part_of_whole_pipeline
    pipeline = @loader.load(fixture("root_with_downstream.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    assert_equal 2, report[:summary][:total_pipeline_files]
    assert_equal 1, report[:summary][:resolved_downstream_pipelines]
    assert_equal "complete", report[:summary][:analysis_scope]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "unit_tests" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "coverage_report" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "sast" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "scan" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "deploy_test" }[:status]
  end

  def test_policy_loader_exposes_bundled_policy_packs
    packs = GitlabCiAuditor::PolicyLoader.available_packs.map { |pack| pack[:name] }

    assert_includes packs, "balanced"
    assert_includes packs, "strict"
    assert_includes packs, "library"
  end

  def test_changes_rules_are_evaluated_against_changed_files
    pipeline = @loader.load(fixture("changes_rules.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    app_scenario = report[:scenarios].find { |scenario| scenario[:changed_files].include?("src/app.rb") }
    docs_scenario = report[:scenarios].find { |scenario| scenario[:changed_files].include?("docs/readme.md") }

    assert_includes app_scenario[:jobs].map { |job| job[:name] }, "app_quality"
    refute_includes app_scenario[:jobs].map { |job| job[:name] }, "docs_lint"
    assert_includes docs_scenario[:jobs].map { |job| job[:name] }, "docs_lint"
    refute_includes docs_scenario[:jobs].map { |job| job[:name] }, "app_quality"
  end

  def test_external_downstream_can_be_resolved_via_snapshot_manifest
    loader = GitlabCiAuditor::PipelineLoader.new(snapshot_file: fixture("external_project_snapshots.json"))
    pipeline = loader.load(fixture("external_project_root.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    assert_equal 2, report[:summary][:total_pipeline_files]
    assert_equal "complete", report[:summary][:analysis_scope]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "unit_tests" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "coverage_report" }[:status]
  end

  def test_library_policy_pack_can_disable_test_deploy_requirement
    pipeline = @loader.load(fixture("quality_without_deploy.yml"))

    balanced_report = GitlabCiAuditor::Analyzer.new(
      pipeline,
      GitlabCiAuditor::PolicyLoader.load(pack: "balanced")
    ).analyze
    library_report = GitlabCiAuditor::Analyzer.new(
      pipeline,
      GitlabCiAuditor::PolicyLoader.load(pack: "library")
    ).analyze

    assert_equal "fail", balanced_report[:categories].find { |category| category[:key] == "deploy_test" }[:status]
    assert_equal "disabled", library_report[:categories].find { |category| category[:key] == "deploy_test" }[:status]
    refute library_report[:ssdlc_findings].any? { |finding| finding[:title].include?("Automated test deployment") }
    assert_equal "Library / Package", library_report[:summary][:policy_pack_label]
  end

  def test_html_report_is_rendered_in_english
    pipeline = @loader.load(fixture("good_pipeline.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze
    html = GitlabCiAuditor::ReportRenderer.new(report).render_html

    assert_includes html, "Pipeline Flow Graph"
    assert_includes html, "Global Recommendations"
    assert_includes html, "Policy Pack:"
    refute_includes html, "Przegląd"
    refute_includes html, "Raport SSDLC"
  end

  def test_renderer_supports_csv_pdf_and_json_bundle_exports
    pipeline = @loader.load(fixture("good_pipeline.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze
    renderer = GitlabCiAuditor::ReportRenderer.new(report)

    csv_output = renderer.render_csv
    pdf_output = renderer.render_pdf
    bundle_output = renderer.render_json_bundle

    assert_includes csv_output, "row_type,section,key,label,status,severity,score,max_score,summary,issue,recommendation,how_to_fix,evidence"
    assert pdf_output.start_with?("%PDF-1.4")
    assert_includes bundle_output, "\"format\": \"json_bundle\""
  end

  private

  def fixture(name)
    File.expand_path(File.join("fixtures", name), __dir__)
  end

  def repo_pipeline
    File.expand_path(File.join("..", "..", "..", ".gitlab-ci.yml"), __dir__)
  end
end
