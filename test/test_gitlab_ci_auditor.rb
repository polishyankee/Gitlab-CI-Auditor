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
    assert report[:scenarios].any? { |scenario| scenario[:status] == "pass" }
  end

  def test_repository_pipeline_reports_missing_ssdlc_controls
    pipeline = @loader.load(repo_pipeline)
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    unit_tests = report[:categories].find { |category| category[:key] == "unit_tests" }
    sast = report[:categories].find { |category| category[:key] == "sast" }
    scan = report[:categories].find { |category| category[:key] == "scan" }
    deploy_test = report[:categories].find { |category| category[:key] == "deploy_test" }

    assert_equal "fail", unit_tests[:status]
    assert_equal "fail", sast[:status]
    assert_equal "fail", scan[:status]
    assert_equal "fail", deploy_test[:status]
    assert report[:recommendations].any? { |item| item.include?("workflow:rules") }
  end

  def test_build_jobs_can_satisfy_unit_test_control_without_dedicated_test_job
    pipeline = @loader.load(fixture("build_embedded_tests.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    unit_tests = report[:categories].find { |category| category[:key] == "unit_tests" }
    scenario = report[:scenarios].find { |item| item[:status] != "skipped" }
    classified_jobs = scenario[:jobs].select { |job| job[:classifications].include?("unit_tests") }.map { |job| job[:name] }

    assert_equal "pass", unit_tests[:status]
    assert_includes classified_jobs, "maven_build"
    assert_includes classified_jobs, "gradle_build"
    assert_includes classified_jobs, "jacoco_artifacts_build"
    refute_includes classified_jobs, "skipped_tests_build"
  end

  def test_downstream_child_pipeline_is_scanned_as_part_of_whole_pipeline
    pipeline = @loader.load(fixture("root_with_downstream.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    assert_equal 2, report[:summary][:total_pipeline_files]
    assert_equal 1, report[:summary][:resolved_downstream_pipelines]
    assert_equal "complete", report[:summary][:analysis_scope]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "unit_tests" }[:status]
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

  private

  def fixture(name)
    File.expand_path(File.join("fixtures", name), __dir__)
  end

  def repo_pipeline
    File.expand_path(File.join("..", "..", "..", ".gitlab-ci.yml"), __dir__)
  end
end
