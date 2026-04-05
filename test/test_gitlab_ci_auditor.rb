require_relative "test_helper"

class GitlabCiAuditorIntegrationTest < Minitest::Test
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
    assert_equal "pass", report.dig(:lint, :status)
    assert report[:categories].find { |category| category[:key] == "unit_tests" }[:score] >= 10
    assert_equal "pass", report[:categories].find { |category| category[:key] == "coverage_report" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "secret_detection" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "iac" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "dast" }[:status]
    assert report[:scenarios].any? { |scenario| scenario[:status] == "pass" }
  end

  def test_legacy_pipeline_reports_missing_ssdlc_controls
    pipeline = @loader.load(example_path("pipelines/legacy_monolith.gitlab-ci.yml"))
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
    assert_equal "warn", deploy_test[:status]
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

  def test_stack_specific_sast_tools_satisfy_the_sast_control
    pipeline = @loader.load(fixture("stack_specific_sast.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    sast = report[:categories].find { |category| category[:key] == "sast" }
    scenario = report[:scenarios].find { |item| item[:status] != "skipped" }
    sast_jobs = scenario[:jobs].select { |job| job[:classifications].include?("sast") }.map { |job| job[:name] }

    assert_equal "pass", sast[:status]
    assert_includes sast_jobs, "dotnet_code_analysis"
    assert_includes sast_jobs, "node_source_review"
  end

  def test_sonarqube_commands_are_recognized_as_sast
    pipeline = @loader.load(fixture("sonarqube_job.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    sast = report[:categories].find { |category| category[:key] == "sast" }
    scenario = report[:scenarios].find { |item| item[:status] != "skipped" }
    sonarqube_job = scenario[:jobs].find { |job| job[:name] == "sonarqube_scan" }

    assert_equal "pass", sast[:status]
    refute_nil sonarqube_job
    assert_includes sonarqube_job[:classifications], "sast"
    assert_includes sonarqube_job[:sast_tools], "sonar_scanner"
    assert_includes report.dig(:metadata, :detected_security_tools, :sast), "SonarQube / sonar-scanner"
  end

  def test_local_shell_script_content_is_used_for_trivy_scan_detection
    pipeline = @loader.load(fixture("script_backed_trivy.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    scan = report[:categories].find { |category| category[:key] == "scan" }
    scenario = report[:scenarios].find { |item| item[:status] != "skipped" }
    trivy_job = scenario[:jobs].find { |job| job[:name] == "trivy_dependency" }

    assert_equal "pass", scan[:status]
    refute_nil trivy_job
    assert_includes trivy_job[:classifications], "artifact_scan"
    assert_includes trivy_job[:artifact_scan_tools], "trivy_fs"
    assert_includes trivy_job[:script_evidence_files].join(" "), "test/fixtures/ci/trivy.sh"
    assert_includes report.dig(:metadata, :detected_security_tools, :artifact_scan), "trivy fs"
  end

  def test_sast_guidance_is_adapted_to_detected_dotnet_and_node_stacks
    pipeline = @loader.load(fixture("polyglot_without_sast.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze
    sast_finding = report[:ssdlc_findings].find { |finding| finding[:title] == "SAST gate is not complete" }

    refute_nil sast_finding
    assert_includes sast_finding[:recommendation], ".NET"
    assert_includes sast_finding[:recommendation], "Node / JS"
    assert_includes sast_finding[:how_to_fix], "dotnet sonarscanner"
    assert_includes sast_finding[:how_to_fix], "njsscan"
  end

  def test_stack_policy_rules_require_stack_appropriate_sast_tools
    pipeline = @loader.load(fixture("mismatched_sast.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze
    sast = report[:categories].find { |category| category[:key] == "sast" }
    sast_finding = report[:ssdlc_findings].find { |finding| finding[:title] == "SAST gate is not complete" }

    assert_equal "warn", sast[:status]
    refute_nil sast_finding
    assert_includes sast_finding[:recommendation], "Node / JS"
    assert_includes sast_finding[:recommendation], "Python"
    assert_includes sast_finding[:how_to_fix], "njsscan"
    assert_includes sast_finding[:how_to_fix], "bandit"
    assert_includes sast_finding[:evidence].join(" "), "Detected Node / JS"
    assert_includes sast_finding[:evidence].join(" "), "Detected Python"
  end

  def test_owasp_samm_benchmark_uses_pipeline_evidence
    pipeline = @loader.load(fixture("samm_benchmark_strong.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze
    benchmark = report.dig(:benchmarks, :owasp_samm_v2)
    secure_build = benchmark[:practices].find { |practice| practice[:key] == "secure_build" }
    secure_deployment = benchmark[:practices].find { |practice| practice[:key] == "secure_deployment" }
    defect_management = benchmark[:practices].find { |practice| practice[:key] == "defect_management" }
    signals = benchmark[:observed_signals]
    analysis_scope = signals.find { |group| group[:key] == "analysis_scope" }
    security_tooling = signals.find { |group| group[:key] == "security_tooling" }
    secure_build_sast_rule = secure_build[:rules].find { |rule| rule[:title] == "Stack-aware SAST is enforced in the build flow" }

    assert_equal "OWASP SAMM v2", benchmark[:framework]
    assert_equal "Implementation", benchmark[:scope]
    assert_equal 3, secure_build[:estimated_level]
    assert_equal 3, secure_deployment[:estimated_level]
    assert defect_management[:estimated_level] >= 2
    refute_empty signals
    assert_includes analysis_scope[:values], "Analysis scope: complete"
    assert security_tooling[:values].any? { |value| value.include?("Artifact scan families:") && value.include?("trivy fs") }
    refute_nil secure_build_sast_rule
    assert_equal "pass", secure_build_sast_rule[:status]
    assert_includes report.dig(:metadata, :detected_security_tools, :artifact_scan), "trivy fs"
    assert_includes report.dig(:metadata, :detected_security_tools, :image_scan), "trivy image"
    assert_includes report.dig(:metadata, :detected_security_tools, :secret_management), "HashiCorp Vault"
    assert_includes report.dig(:metadata, :detected_security_tools, :integrity_verification), "cosign verify"
  end

  def test_owasp_samm_benchmark_maps_all_implementation_questions
    pipeline = @loader.load(example_path("pipelines/samm_question_rich.gitlab-ci.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze
    benchmark = report.dig(:benchmarks, :owasp_samm_v2)
    secure_build = benchmark[:practices].find { |practice| practice[:key] == "secure_build" }
    secure_deployment = benchmark[:practices].find { |practice| practice[:key] == "secure_deployment" }
    defect_management = benchmark[:practices].find { |practice| practice[:key] == "defect_management" }
    mapped_questions = benchmark[:practices].sum { |practice| practice[:questions].size }
    question_signal = benchmark[:observed_signals].find { |group| group[:key] == "question_mapping" }

    assert_equal 18, mapped_questions
    assert_equal 6, secure_build[:questions].size
    assert_equal 6, secure_deployment[:questions].size
    assert_equal 6, defect_management[:questions].size
    assert_equal "pass", secure_build[:questions].find { |question| question[:key] == "I-SB-1-A" }[:status]
    assert_equal "pass", secure_deployment[:questions].find { |question| question[:key] == "I-SD-3-A" }[:status]
    assert_equal "review", defect_management[:questions].find { |question| question[:key] == "I-DM-2-A" }[:status]
    assert_includes question_signal[:values], "Mapped implementation questions: 18"
  end

  def test_context_manifest_can_expand_multi_project_scope
    pipeline = GitlabCiAuditor::ContextLoader.new(context_file: fixture("context_manifest.json")).load(fixture("context_root.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    assert_equal 2, report[:summary][:total_pipeline_files]
    assert_equal "complete", report[:summary][:analysis_scope]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "sbom" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "secret_detection" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "iac" }[:status]
    assert_equal "pass", report[:categories].find { |category| category[:key] == "dast" }[:status]
    assert report[:graph][:edges].any? { |edge| edge[:type] == "context" }
  end

  def test_graph_nodes_expose_short_pipeline_labels_for_long_paths
    pipeline = @loader.load(example_path("pipelines/library_package.gitlab-ci.yml"))
    report = GitlabCiAuditor::Analyzer.new(
      pipeline,
      GitlabCiAuditor::PolicyLoader.load(pack: "library")
    ).analyze
    graph_node = report[:graph][:nodes].find { |node| node[:pipeline_label].include?("examples/pipelines/") }

    refute_nil graph_node
    assert_equal ".../pipelines/library_package.gitlab-ci.yml", graph_node[:pipeline_short_label]
  end

  def test_policy_can_tune_finding_severity_per_organization
    policy = GitlabCiAuditor.deep_copy(GitlabCiAuditor::PolicyLoader.load(pack: "balanced"))
    policy["severity_tuning"] = {
      "ssdlc" => {
        "exact" => {
          "SAST gate is not complete" => "high"
        }
      }
    }

    pipeline = @loader.load(fixture("mismatched_sast.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline, policy).analyze
    sast_finding = report[:ssdlc_findings].find { |finding| finding[:title] == "SAST gate is not complete" }

    refute_nil sast_finding
    assert_equal "high", sast_finding[:severity]
    assert_equal "medium", sast_finding[:base_severity]
    assert_equal "policy_tuning", sast_finding[:severity_source]
  end

  def test_graph_includes_gate_overlays_legend_and_critical_path
    pipeline = @loader.load(fixture("good_pipeline.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze
    graph = report[:graph]
    critical_nodes = graph[:nodes].select { |node| node[:critical_path] }

    assert graph.dig(:legend, :node_variants).any?
    assert graph.dig(:legend, :edge_variants).any? { |item| item[:edge_type] == "critical" }
    assert graph.dig(:legend, :gate_overlays).any? { |item| item[:state] == "blocking" }
    assert critical_nodes.any?
    assert critical_nodes.any? { |node| node[:gate_overlays].any? }
    assert_equal true, graph[:edges].any? { |edge| edge[:critical_path] }
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

  def test_argocd_deployment_repo_can_satisfy_test_deploy_control_via_snapshot
    loader = GitlabCiAuditor::PipelineLoader.new(snapshot_file: fixture("argocd_external_snapshots.json"))
    pipeline = loader.load(fixture("argocd_root.yml"))
    report = GitlabCiAuditor::Analyzer.new(pipeline).analyze

    deploy_test = report[:categories].find { |category| category[:key] == "deploy_test" }
    scenario = report[:scenarios].find { |item| item[:status] != "skipped" }
    deploy_job = scenario[:jobs].find { |job| job[:name] == "deploy_test" }

    assert_equal "pass", deploy_test[:status]
    refute_nil deploy_job
    assert_includes deploy_job[:classifications], "deploy_test"
    assert_includes deploy_job[:script_evidence_files].join(" "), "test/fixtures/scripts/argocd-sync.sh"
    assert_equal 2, report[:summary][:total_pipeline_files]
    assert_equal "complete", report[:summary][:analysis_scope]
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
end
