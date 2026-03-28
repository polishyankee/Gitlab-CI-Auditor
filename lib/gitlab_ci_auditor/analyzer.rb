module GitlabCiAuditor
  class Analyzer
    DEFAULT_POLICY = GitlabCiAuditor::PolicyLoader.load
    CONTROL_KEYS = %i[unit_tests coverage_report sast scan deploy_test].freeze

    class ScenarioBuilder
      BASE_BRANCHES = [
        "main",
        "master",
        "develop",
        "feature/audit-coverage",
        "release/1.0.0",
        "hotfix/urgent-fix",
        "test"
      ].freeze

      def initialize(pipeline)
        @pipeline = pipeline
      end

      def build
        expressions = collect_rule_expressions
        change_groups = collect_change_groups
        default_branch = infer_default_branch(expressions)
        branches = (BASE_BRANCHES + discovered_branches(expressions) + [default_branch]).compact.uniq
        sources = discovered_sources(expressions)
        scenarios = []

        branches.each do |branch|
          scenarios << build_branch_scenario("push", branch, default_branch)
        end

        if sources.include?("merge_request_event") || expressions.any? { |expr| expr.include?("CI_MERGE_REQUEST") }
          scenarios << build_merge_request_scenario(default_branch)
        else
          scenarios << build_merge_request_scenario(default_branch)
        end

        scenarios << build_branch_scenario("schedule", default_branch, default_branch) if sources.include?("schedule") || sources.empty?
        scenarios << build_branch_scenario("web", default_branch, default_branch) if sources.include?("web") || sources.empty?
        scenarios << build_branch_scenario("api", default_branch, default_branch) if sources.include?("api")
        scenarios << build_tag_scenario(default_branch)

        if change_groups.any?
          scenarios = scenarios.flat_map do |scenario|
            build_change_variants(scenario, change_groups)
          end
        end

        scenarios.uniq { |scenario| scenario[:id] }
      end

      private

      def collect_rule_expressions
        expressions = []
        pipeline_list(@pipeline).each do |pipeline|
          Array(pipeline.workflow["rules"]).each do |rule|
            expressions << rule["if"].to_s if rule.is_a?(Hash) && rule["if"]
          end

          pipeline.jobs.each_value do |job|
            Array(job["rules"]).each do |rule|
              expressions << rule["if"].to_s if rule.is_a?(Hash) && rule["if"]
            end

            Array(job["only"]).each { |item| expressions << item.to_s }
            Array(job["except"]).each { |item| expressions << item.to_s }
          end
        end
        expressions
      end

      def collect_change_groups
        groups = []

        pipeline_list(@pipeline).each do |pipeline|
          Array(pipeline.workflow["rules"]).each_with_index do |rule, index|
            next unless rule.is_a?(Hash) && rule.key?("changes")

            append_change_group(groups, rule["changes"], "workflow", index, pipeline.base_dir)
          end

          pipeline.jobs.each do |job_name, job|
            Array(job["rules"]).each_with_index do |rule, index|
              next unless rule.is_a?(Hash) && rule.key?("changes")

              append_change_group(groups, rule["changes"], "job #{job_name}", index, pipeline.base_dir)
            end
          end
        end

        groups.uniq { |group| group[:fingerprint] }
      end

      def append_change_group(groups, changes_value, origin, index, base_dir)
        patterns = extract_change_patterns(changes_value)
        return if patterns.empty?

        compare_to = changes_value.is_a?(Hash) ? changes_value["compare_to"].to_s : nil
        groups << {
          origin: origin,
          index: index,
          patterns: patterns,
          compare_to: compare_to,
          sample_files: sample_changed_files(patterns, base_dir),
          fingerprint: "#{origin}|#{compare_to}|#{patterns.join('|')}"
        }
      end

      def extract_change_patterns(changes_value)
        case changes_value
        when Hash
          GitlabCiAuditor.normalize_array(changes_value["paths"] || changes_value[:paths] || changes_value["changes"])
        else
          GitlabCiAuditor.normalize_array(changes_value)
        end
      end

      def build_change_variants(scenario, change_groups)
        matching_variants = change_groups.map.with_index do |group, index|
          sample_files = group[:sample_files]
          label_suffix = sample_files.any? ? sample_files.join(", ") : group[:patterns].first
          compare_suffix = group[:compare_to].to_s.empty? ? "" : " vs #{group[:compare_to]}"
          scenario.merge(
            id: "#{scenario[:id]}-changes-#{index}",
            label: "#{scenario[:label]} + changes #{label_suffix}#{compare_suffix}",
            changed_files: sample_files,
            changes_context: {
              origin: group[:origin],
              patterns: group[:patterns],
              compare_to: group[:compare_to]
            }
          )
        end

        matching_variants + [
          scenario.merge(
            id: "#{scenario[:id]}-nochanges",
            label: "#{scenario[:label]} + no matching changes",
            changed_files: [],
            changes_context: {
              origin: "none",
              patterns: [],
              compare_to: nil
            }
          )
        ]
      end

      def sample_changed_files(patterns, base_dir)
        patterns.map { |pattern| sample_file_for_pattern(pattern, base_dir) }.compact.uniq.first(3)
      end

      def sample_file_for_pattern(pattern, base_dir)
        normalized = pattern.to_s.strip.sub(%r{\A\./}, "")
        return if normalized.empty?

        matches = Dir.glob(File.join(base_dir, normalized), File::FNM_EXTGLOB | File::FNM_DOTMATCH).reject { |path| File.directory?(path) }
        return matches.first.sub(%r{\A#{Regexp.escape(base_dir)}/?}, "") if matches.any?

        synthetic = normalized.dup
        synthetic = synthetic.sub(/\{([^}]+)\}/) { Regexp.last_match(1).split(",").first.to_s }
        synthetic = synthetic.gsub("**/", "src/")
        synthetic = synthetic.gsub("*", "sample")
        synthetic = synthetic.gsub("?", "x")
        synthetic = synthetic.gsub(/\[[^\]]+\]/, "a")
        synthetic = synthetic.gsub(/[{}]/, "")
        synthetic = synthetic.sub(%r{\A/+}, "")
        synthetic = "src/sample.txt" if synthetic.empty?
        synthetic += "/sample.txt" if synthetic.end_with?("/")
        synthetic
      end

      def pipeline_list(pipeline, seen = {})
        return [] if seen[pipeline.object_id]

        seen[pipeline.object_id] = true
        collected = [pipeline]
        pipeline.downstream_references.each do |reference|
          next unless reference.pipeline

          collected.concat(pipeline_list(reference.pipeline, seen))
        end
        collected
      end

      def infer_default_branch(expressions)
        return "main" if expressions.any? { |expression| expression.match?(/["']main["']/) }
        return "master" if expressions.any? { |expression| expression.match?(/["']master["']/) }

        "main"
      end

      def discovered_branches(expressions)
        branches = []

        expressions.each do |expression|
          expression.scan(/\$CI_(?:COMMIT_BRANCH|COMMIT_REF_NAME|DEFAULT_BRANCH)\s*==\s*["']([^"']+)["']/) do |match|
            branches << match.first
          end

          expression.scan(/\$CI_(?:COMMIT_BRANCH|COMMIT_REF_NAME)\s*=~\s*\/(.+?)\//) do |match|
            sample = sample_branch_for_regex(match.first)
            branches << sample if sample
          end
        end

        branches
      end

      def discovered_sources(expressions)
        sources = []
        expressions.each do |expression|
          expression.scan(/\$CI_PIPELINE_SOURCE\s*==\s*["']([^"']+)["']/) do |match|
            sources << match.first
          end

          sources << "merge_request_event" if expression.include?("CI_MERGE_REQUEST")
          sources << "push" if expression.include?("CI_COMMIT_BRANCH")
        end

        sources.uniq
      end

      def sample_branch_for_regex(pattern)
        case pattern
        when /release/
          "release/2.0.0"
        when /hotfix/
          "hotfix/critical"
        when /feature/
          "feature/regex-match"
        when /develop/
          "develop"
        when /master/
          "master"
        when /main/
          "main"
        else
          literal = pattern.gsub(/[\^\$\(\)\[\]\+\*\?\\]/, "").split("|").first
          return nil if literal.nil? || literal.empty?

          literal.include?("/") ? literal : "#{literal}/sample"
        end
      end

      def build_branch_scenario(source, branch, default_branch)
        {
          id: "#{source}-#{branch.gsub(/[^a-zA-Z0-9]+/, "-")}",
          label: "#{source} -> #{branch}",
          source: source,
          branch: branch,
          tag: nil,
          default_branch: default_branch,
          changed_files: [],
          changes_context: nil,
          variables: build_variables(source: source, branch: branch, tag: nil, default_branch: default_branch, mr_target: nil)
        }
      end

      def build_merge_request_scenario(default_branch)
        branch = "feature/merge-request"
        {
          id: "merge-request-#{default_branch}",
          label: "merge_request_event #{branch} -> #{default_branch}",
          source: "merge_request_event",
          branch: branch,
          tag: nil,
          default_branch: default_branch,
          changed_files: [],
          changes_context: nil,
          variables: build_variables(
            source: "merge_request_event",
            branch: branch,
            tag: nil,
            default_branch: default_branch,
            mr_target: default_branch
          )
        }
      end

      def build_tag_scenario(default_branch)
        tag = "v1.0.0"
        {
          id: "tag-#{tag.tr('.', '-')}",
          label: "tag #{tag}",
          source: "push",
          branch: nil,
          tag: tag,
          default_branch: default_branch,
          changed_files: [],
          changes_context: nil,
          variables: build_variables(source: "push", branch: nil, tag: tag, default_branch: default_branch, mr_target: nil)
        }
      end

      def build_variables(source:, branch:, tag:, default_branch:, mr_target:)
        {
          "CI_PIPELINE_SOURCE" => source,
          "CI_COMMIT_BRANCH" => branch,
          "CI_COMMIT_TAG" => tag,
          "CI_COMMIT_REF_NAME" => tag || branch,
          "CI_DEFAULT_BRANCH" => default_branch,
          "CI_MERGE_REQUEST_TARGET_BRANCH_NAME" => mr_target,
          "CI_COMMIT_REF_PROTECTED" => ((branch == default_branch || branch.to_s.start_with?("release/")) ? "true" : "false")
        }
      end
    end

    def initialize(pipeline, policy = nil)
      @pipeline = pipeline
      @policy = policy || DEFAULT_POLICY
      @template_features = extract_template_features
    end

    def analyze
      scenarios = ScenarioBuilder.new(@pipeline).build
      active_scenarios = []
      inactive_scenarios = []

      scenarios.each do |scenario|
        if pipeline_active?(@pipeline, scenario)
          active_scenarios << analyze_scenario(scenario)
        else
          inactive_scenarios << {
            id: scenario[:id],
            label: scenario[:label],
            status: "skipped",
            reason: "workflow rules prevented pipeline creation",
            changed_files: Array(scenario[:changed_files]),
            changes_context: scenario[:changes_context]
          }
        end
      end

      security_findings = security_policy_findings
      maintainability = maintainability_findings
      coverage = coverage_summary(active_scenarios)
      categories = build_categories(active_scenarios, coverage, security_findings, maintainability)
      overall_score = categories.sum { |category| category[:score] }
      strengths = strengths(active_scenarios, security_findings, maintainability)
      recommendations = recommendations(coverage, security_findings, maintainability, inactive_scenarios)
      ssdlc_findings = build_ssdlc_findings(active_scenarios, coverage, inactive_scenarios)
      pipeline_files = all_pipelines
      resolved_downstreams = pipeline_files.flat_map(&:downstream_references).select { |reference| reference.pipeline }.map(&:pipeline_path).compact.uniq
      unresolved_downstreams = unresolved_downstream_references
      graph = build_pipeline_graph
      policy_meta = normalized_policy_meta

      {
        generated_at: Time.now.utc.iso8601,
        pipeline_path: @pipeline.path,
        summary: {
          overall_score: overall_score,
          max_score: categories.sum { |category| category[:max_score] },
          grade: grade_for(overall_score),
          status: status_for_score(overall_score),
          active_scenarios: active_scenarios.size,
          skipped_scenarios: inactive_scenarios.size,
          total_jobs: total_job_count,
          total_stages: effective_stages.size,
          total_pipeline_files: pipeline_files.size,
          resolved_downstream_pipelines: resolved_downstreams.size,
          unresolved_downstream_pipelines: unresolved_downstreams.size,
          analysis_scope: unresolved_downstreams.empty? ? "complete" : "partial",
          policy_pack_name: policy_meta[:name],
          policy_pack_label: policy_meta[:label],
          policy_source: policy_meta[:source]
        },
        categories: categories,
        graph: graph,
        scenarios: active_scenarios + inactive_scenarios,
        ssdlc_findings: ssdlc_findings,
        strengths: strengths,
        recommendations: recommendations,
        security_findings: security_findings,
        maintainability: maintainability,
        loader_warnings: aggregate_loader_warnings,
        metadata: {
          template_includes: pipeline_files.flat_map { |pipeline| pipeline.include_metadata[:template_includes] }.uniq,
          resolved_local_includes: pipeline_files.flat_map { |pipeline| pipeline.include_metadata[:resolved_local_includes] }.uniq,
          unresolved_includes: pipeline_files.flat_map { |pipeline| pipeline.include_metadata[:unresolved_includes] }.uniq,
          resolved_downstream_pipelines: resolved_downstreams,
          unresolved_downstream_pipelines: unresolved_downstreams.map do |reference|
            {
              trigger_job_name: reference.trigger_job_name,
              kind: reference.kind,
              pipeline_path: reference.pipeline_path,
              warning: reference.warning
            }
          end
        }
      }
    end

    private

    def analyze_scenario(scenario)
      active_jobs = analyze_pipeline_scenario(@pipeline, scenario)

      controls = scenario_controls(active_jobs)
      {
        id: scenario[:id],
        label: scenario[:label],
        source: scenario[:source],
        branch: scenario[:branch],
        tag: scenario[:tag],
        changed_files: Array(scenario[:changed_files]),
        changes_context: scenario[:changes_context],
        status: scenario_status(controls),
        jobs: active_jobs,
        downstream_warnings: active_jobs.flat_map { |job| Array(job[:downstream_warnings]) }.uniq,
        controls: controls
      }
    end

    def analyze_pipeline_scenario(pipeline, scenario, inherited_gate = {}, trigger_chain = [])
      return [] unless pipeline_active?(pipeline, scenario)

      rule_evaluator = RuleEvaluator.new(pipeline)
      pipeline.jobs.each_with_object([]) do |(job_name, job), jobs|
        evaluation = rule_evaluator.evaluate_job(job_name, job, scenario)
        next unless evaluation[:included]

        job_description = describe_job(pipeline, job_name, job, evaluation, inherited_gate, trigger_chain)
        jobs << job_description

        child_gate = {
          manual: job_description[:manual],
          allow_failure: job_description[:allow_failure]
        }

        pipeline.downstream_references.select { |reference| reference.trigger_job_name == job_name }.each do |reference|
          if reference.pipeline
            jobs.concat(
              analyze_pipeline_scenario(
                reference.pipeline,
                scenario,
                child_gate,
                trigger_chain + ["#{job_name}@#{relative_pipeline_path(pipeline.path)}"]
              )
            )
          else
            job_description[:downstream_warnings] << (reference.warning || "Unresolved downstream pipeline")
          end
        end
      end
    end

    def pipeline_active?(pipeline, scenario)
      RuleEvaluator.new(pipeline).pipeline_active?(scenario)
    end

    def describe_job(pipeline, job_name, job, evaluation, inherited_gate = {}, trigger_chain = [])
      script_lines = collect_script_lines(pipeline, job)
      environment_name = extract_environment_name(job)
      image_name = extract_image_name(job["image"] || pipeline.raw_config["image"])
      artifact_strings = collect_artifact_strings(job["artifacts"])
      classifications = classify_job(job_name, job, script_lines, artifact_strings, environment_name)
      inherited_manual = inherited_gate[:manual] == true
      inherited_allow_failure = inherited_gate[:allow_failure] == true

      {
        name: job_name,
        stage: (job["stage"] || "test").to_s,
        when: evaluation[:when],
        manual: inherited_manual || evaluation[:manual],
        allow_failure: inherited_allow_failure || evaluation[:allow_failure],
        image: image_name,
        environment: environment_name,
        artifacts: artifact_strings,
        script_lines: script_lines,
        classifications: classifications,
        pipeline_path: pipeline.path,
        pipeline_label: relative_pipeline_path(pipeline.path),
        trigger_chain: trigger_chain,
        downstream_warnings: []
      }
    end

    def collect_script_lines(pipeline, job)
      lines = []
      lines.concat(pipeline.global_before_script)
      lines.concat(GitlabCiAuditor.normalize_array(job["before_script"]))
      lines.concat(GitlabCiAuditor.normalize_array(job["script"]))
      lines.concat(GitlabCiAuditor.normalize_array(job["after_script"]))
      lines.concat(pipeline.global_after_script)
      lines.map(&:strip).reject(&:empty?)
    end

    def extract_environment_name(job)
      environment = job["environment"]
      return environment["name"].to_s if environment.is_a?(Hash) && environment["name"]
      return environment.to_s unless environment.nil?

      nil
    end

    def extract_image_name(image)
      case image
      when Hash
        image["name"].to_s
      when nil
        nil
      else
        image.to_s
      end
    end

    def classify_job(job_name, job, script_lines, artifact_strings, environment_name)
      text = [
        job_name,
        job["stage"],
        environment_name,
        extract_image_name(job["image"]),
        artifact_strings.join("\n"),
        script_lines.join("\n")
      ].compact.join("\n").downcase

      classifications = []
      classifications << "unit_tests" if unit_test_job?(script_lines, artifact_strings, text)
      classifications << "coverage_report" if coverage_report_job?(artifact_strings)
      classifications << "sast" if sast_job?(text)
      classifications << "artifact_scan" if artifact_scan_job?(text)
      classifications << "image_scan" if image_scan_job?(text)
      classifications << "deploy_test" if deploy_test_job?(text, environment_name)
      classifications << "deploy_prod" if deploy_production_job?(environment_name)
      classifications
    end

    def unit_test_job?(script_lines, artifact_strings, text)
      return true if coverage_report_job?(artifact_strings)
      return true if explicit_unit_test_command?(text)

      normalized_lines = script_lines.map(&:downcase)
      normalized_lines.any? do |line|
        maven_command_runs_tests?(line) || gradle_command_runs_tests?(line)
      end
    end

    def coverage_report_job?(artifact_strings)
      artifact_strings.any? do |entry|
        entry.to_s.downcase.match?(/jacoco(?:\.exec|\.xml)?|site\/jacoco|jacoco\/.*\.xml|cobertura(?:-coverage)?\.xml|lcov\.info|coverage\/.*\.(xml|exec|info)/)
      end
    end

    def sast_job?(text)
      text.match?(/\b(sast|semgrep|sonarqube|sonar-scanner|bandit|brakeman|gosec|spotbugs|checkov|kics|codeql)\b/)
    end

    def artifact_scan_job?(text)
      text.match?(/\b(dependency[- ]scanning|dependency-check|owasp|trivy fs|grype|artifact scan|license[- ]scanning|snyk test)\b/)
    end

    def image_scan_job?(text)
      text.match?(/\b(container[- ]scanning|trivy image|grype|docker scan|snyk container|anchore)\b/)
    end

    def deploy_test_job?(text, environment_name)
      deployment_like = text.match?(/\b(deploy|kubectl apply|helm upgrade|ansible-playbook|terraform apply|oc apply|scp |rsync )\b/)
      non_prod_env = environment_name.to_s.match?(environment_pattern(@policy["test_environments"]))
      deployment_like && non_prod_env
    end

    def deploy_production_job?(environment_name)
      environment_name.to_s.match?(environment_pattern(@policy["production_environments"]))
    end

    def scenario_controls(active_jobs)
      controls = {
        unit_tests: control_required?(:unit_tests) ? control_state_for(active_jobs, "unit_tests") : disabled_control("Disabled by the selected policy pack"),
        coverage_report: control_required?(:coverage_report) ? control_state_for(active_jobs, "coverage_report") : disabled_control("Disabled by the selected policy pack"),
        sast: control_required?(:sast) ? control_state_for(active_jobs, "sast") : disabled_control("Disabled by the selected policy pack"),
        scan: control_required?(:scan) ? scan_control_state(active_jobs) : disabled_control("Disabled by the selected policy pack"),
        deploy_test: control_required?(:deploy_test) ? control_state_for(active_jobs, "deploy_test") : disabled_control("Disabled by the selected policy pack")
      }

      apply_template_inferences(controls)
    end

    def control_state_for(active_jobs, classification)
      matching = active_jobs.select { |job| job[:classifications].include?(classification) }
      return missing_control if matching.empty?

      enforced = matching.reject { |job| job[:manual] || job[:allow_failure] }
      if enforced.any?
        pass_control(enforced.map { |job| "#{job[:name]} (#{job[:stage]})" })
      else
        warn_control(matching.map { |job| "#{job[:name]} is present but not enforcing" })
      end
    end

    def scan_control_state(active_jobs)
      artifact_state = control_state_for(active_jobs, "artifact_scan")
      image_state = control_state_for(active_jobs, "image_scan")
      return artifact_state if artifact_state[:status] == "pass"
      return image_state if image_state[:status] == "pass"
      return warn_control((artifact_state[:evidence] + image_state[:evidence]).uniq) if [artifact_state, image_state].any? { |state| state[:status] == "warn" }

      missing_control
    end

    def apply_template_inferences(controls)
      controls[:sast] = template_override("sast", controls[:sast])
      controls[:scan] = template_override("scan", controls[:scan])
      controls
    end

    def template_override(feature_key, existing_state)
      return existing_state unless existing_state[:status] == "missing"
      return existing_state unless @template_features[feature_key]

      warn_control(["Detected GitLab security template include: #{@template_features[feature_key].join(', ')}"])
    end

    def pass_control(evidence)
      { status: "pass", evidence: evidence }
    end

    def warn_control(evidence)
      { status: "warn", evidence: evidence }
    end

    def missing_control
      { status: "missing", evidence: [] }
    end

    def disabled_control(reason)
      { status: "disabled", evidence: [reason] }
    end

    def scenario_status(controls)
      statuses = required_control_keys.map { |key| controls[key][:status] }
      return "pass" if statuses.all? { |status| status == "pass" }
      return "warn" if statuses.any? { |status| status == "warn" } || statuses.any? { |status| status == "pass" }

      "fail"
    end

    def coverage_summary(active_scenarios)
      summary = {
        fully_compliant: 0,
        unit_tests: { pass: 0, warn: 0, missing: 0, disabled: 0 },
        coverage_report: { pass: 0, warn: 0, missing: 0, disabled: 0 },
        sast: { pass: 0, warn: 0, missing: 0, disabled: 0 },
        scan: { pass: 0, warn: 0, missing: 0, disabled: 0 },
        deploy_test: { pass: 0, warn: 0, missing: 0, disabled: 0 }
      }

      active_scenarios.each do |scenario|
        summary[:fully_compliant] += 1 if scenario[:status] == "pass"
        scenario[:controls].each do |key, state|
          summary[key][state[:status].to_sym] += 1
        end
      end

      summary
    end

    def build_categories(active_scenarios, coverage, security_findings, maintainability)
      total = [active_scenarios.size, 1].max.to_f
      fully_compliant = coverage[:fully_compliant] / total
      unit_tests_ratio = ratio_for(coverage[:unit_tests])
      coverage_report_ratio = ratio_for(coverage[:coverage_report])
      sast_ratio = ratio_for(coverage[:sast])
      scan_ratio = ratio_for(coverage[:scan])
      deploy_ratio = ratio_for(coverage[:deploy_test])
      security_ratio = [[10 - security_findings.sum { |finding| severity_weight(finding[:severity]) }, 0].max, 10].min / 10.0
      maintainability_ratio = maintainability[:score].to_f / maintainability[:max_score]

      [
        category("execution_path_coverage", "Execution Path Coverage", 20, fully_compliant, "#{coverage[:fully_compliant]}/#{active_scenarios.size} active scenarios satisfy the selected SSDLC policy pack"),
        category("unit_tests", "Unit Test Execution", 10, unit_tests_ratio, status_summary(coverage[:unit_tests]), required: control_required?(:unit_tests)),
        category("coverage_report", "Coverage Reporting", 5, coverage_report_ratio, status_summary(coverage[:coverage_report]), required: control_required?(:coverage_report)),
        category("sast", "SAST", 15, sast_ratio, status_summary(coverage[:sast]), required: control_required?(:sast)),
        category("scan", "Artifact/Image Scanning", 15, scan_ratio, status_summary(coverage[:scan]), required: control_required?(:scan)),
        category("deploy_test", "Automated Test Deployment", 15, deploy_ratio, status_summary(coverage[:deploy_test]), required: control_required?(:deploy_test)),
        category("security", "Security Policies", 10, security_ratio, security_findings.empty? ? "No material policy violations detected" : "#{security_findings.size} security policy violations detected"),
        {
          key: "maintainability",
          title: "Maintainability and Complexity",
          score: maintainability[:score],
          max_score: maintainability[:max_score],
          status: score_status(maintainability[:score].to_f / maintainability[:max_score]),
          summary: maintainability[:summary]
        }
      ]
    end

    def ratio_for(status_counts)
      total = status_counts[:pass] + status_counts[:warn] + status_counts[:missing]
      return 0.0 if total.zero?

      ((status_counts[:pass] * 1.0) + (status_counts[:warn] * 0.5)) / total
    end

    def severity_weight(severity)
      case severity
      when "high"
        3
      when "medium"
        2
      else
        1
      end
    end

    def category(key, title, max_score, ratio, summary, required: true)
      unless required
        return {
          key: key,
          title: title,
          score: max_score,
          max_score: max_score,
          status: "disabled",
          summary: "Disabled by the selected policy pack"
        }
      end

      score = (ratio * max_score).round
      {
        key: key,
        title: title,
        score: score,
        max_score: max_score,
        status: score_status(ratio),
        summary: summary
      }
    end

    def score_status(ratio)
      return "pass" if ratio >= 0.85
      return "warn" if ratio >= 0.45

      "fail"
    end

    def status_summary(status_counts)
      bits = [
        "#{status_counts[:pass]} pass",
        "#{status_counts[:warn]} warn",
        "#{status_counts[:missing]} missing"
      ]
      bits << "#{status_counts[:disabled]} disabled" if status_counts[:disabled].to_i.positive?
      bits.join(", ")
    end

    def control_required?(key)
      defaults = {
        "coverage_report" => false
      }
      @policy.fetch("required_controls", {}).fetch(key.to_s, defaults.fetch(key.to_s, true))
    end

    def required_control_keys
      CONTROL_KEYS.select { |key| control_required?(key) }
    end

    def extract_template_features
      features = {}
      all_pipelines.each do |pipeline|
        pipeline.include_metadata[:template_includes].each do |template_name|
          downcased = template_name.downcase
          features["sast"] ||= [] if downcased.include?("sast")
          features["scan"] ||= [] if downcased.include?("container-scanning") || downcased.include?("dependency-scanning")
          features["scan"] ||= [] if downcased.include?("license-scanning")
          features["sast"] << template_name if downcased.include?("sast")
          if downcased.include?("container-scanning") || downcased.include?("dependency-scanning") || downcased.include?("license-scanning")
            features["scan"] << template_name
          end
        end
      end
      features
    end

    def security_policy_findings
      findings = []

      each_job_with_image do |pipeline, job_name, image_name|
        job_ref = job_reference(job_name, pipeline)
        if @policy.dig("security_policies", "forbid_latest_images") && image_name.include?(":latest")
          findings << finding(
            "medium",
            "Image #{image_name} uses the latest tag",
            "Job #{job_ref} should use an explicit version or digest.",
            "Pin the image to a concrete version or digest.",
            "Replace `image: #{image_name}` with something like `image: #{image_name.sub(':latest', ':1.2.3')}` or a digest such as `@sha256:...`."
          )
        elsif @policy.dig("security_policies", "forbid_unpinned_images") &&
              !image_name.include?(":") && !image_name.include?("@sha256:")
          findings << finding(
            "low",
            "Image #{image_name} is not versioned",
            "Job #{job_ref} does not declare an explicit image tag.",
            "Add an explicit image version tag.",
            "Use something like `image: #{image_name}:3.19` or a digest such as `#{image_name}@sha256:...`."
          )
        end
      end

      all_pipelines.each do |pipeline|
        pipeline.jobs.each do |job_name, job|
          script_lines = collect_script_lines(pipeline, job)
          job_ref = job_reference(job_name, pipeline)
          if @policy.dig("security_policies", "forbid_remote_script_piping") &&
              script_lines.any? { |line| line.match?(/\b(curl|wget)\b.+\|\s*(sh|bash)\b/) }
            findings << finding(
              "high",
              "Remote script download and execution in #{job_ref}",
              "The job uses a `curl|bash` or `wget|sh` pattern without integrity verification.",
              "Download the artifact explicitly and verify its checksum or signature before execution.",
              "Split the command into two steps, for example `curl -o installer.sh ...` and `sha256sum -c ... && bash installer.sh`."
            )
          end

          if @policy.dig("security_policies", "forbid_strict_host_key_bypass") &&
              script_lines.any? { |line| line.include?("StrictHostKeyChecking no") }
            findings << finding(
              "high",
              "Host key verification disabled in #{job_ref}",
              "SSH trust is bypassed through `StrictHostKeyChecking no`.",
              "Manage `known_hosts` instead of disabling host verification.",
              "Add `ssh-keyscan host >> ~/.ssh/known_hosts` and remove `StrictHostKeyChecking no` from the job configuration."
            )
          end

          classifications = classify_job(
            job_name,
            job,
            script_lines,
            collect_artifact_strings(job["artifacts"]),
            extract_environment_name(job)
          )
          if @policy.dig("security_policies", "forbid_allow_failure_on_security") &&
              job["allow_failure"] == true && (classifications & %w[unit_tests sast artifact_scan image_scan]).any?
            findings << finding(
              "medium",
              "Critical gate #{job_ref} has allow_failure=true",
              "Tests or security scans are present but do not block the pipeline.",
              "Remove `allow_failure: true` from jobs responsible for quality and security.",
              "For job `#{job_name}`, set `allow_failure: false` or remove the key entirely."
            )
          end

          if @policy.dig("security_policies", "forbid_manual_test_deploy") &&
              extract_environment_name(job).to_s.match?(environment_pattern(@policy["test_environments"])) &&
              job["when"].to_s == "manual"
            findings << finding(
              "medium",
              "Test deployment #{job_ref} is manual",
              "The test environment is not deployed automatically after the required gates pass.",
              "Turn the test deployment into an automatic stage after tests and scans.",
              "Remove `when: manual`, set `environment: name: test`, and run the job after `needs` on build, test, and scan jobs."
            )
          end
        end
      end

      if @policy.dig("security_policies", "forbid_inline_secrets")
        all_pipelines.each do |pipeline|
          top_level_sensitive_literals(pipeline.variables).each do |key, value|
            findings << finding(
              "high",
              "Sensitive variable #{key} has a literal value in #{relative_pipeline_path(pipeline.path)}",
              "A literal value #{value.inspect} was detected in the `variables` section.",
              "Move the value to a protected or masked CI variable, or to a secret manager.",
              "Keep only a variable reference in YAML, for example `#{key}: \"$#{key}\"`, and store the value outside the repository."
            )
          end
        end
      end

      findings.uniq { |finding| [finding[:title], finding[:issue]] }
    end

    def top_level_sensitive_literals(variables)
      variables.each_with_object([]) do |(key, value), literals|
        next unless key.to_s.match?(SENSITIVE_KEY_PATTERN)

        literal = if value.is_a?(Hash)
                    value["value"]
                  else
                    value
                  end

        next if literal.nil?

        literal_string = literal.to_s.strip
        next if literal_string.empty? || literal_string.start_with?("$") || literal_string.match?(/\A<.+>\z/)

        literals << [key, literal_string]
      end
    end

    def each_job_with_image
      all_pipelines.each do |pipeline|
        pipeline.jobs.each do |job_name, job|
          image_name = extract_image_name(job["image"] || pipeline.raw_config["image"])
          yield pipeline, job_name, image_name if image_name && !image_name.empty?
        end
      end
    end

    def maintainability_findings
      findings = []
      duplicate_scripts = duplicate_script_groups
      job_count = total_job_count
      global_variables = all_pipelines.sum { |pipeline| pipeline.variables.size }
      rule_complexity = max_rule_complexity
      long_script_jobs = collect_long_job_names
      deprecated_jobs = all_pipelines.flat_map do |pipeline|
        pipeline.jobs.select { |_name, job| job.key?("only") || job.key?("except") }.keys.map { |job_name| job_reference(job_name, pipeline) }
      end
      undefined_stage_jobs = all_pipelines.each_with_object([]) do |pipeline, jobs|
        pipeline.jobs.each do |job_name, job|
          stage = (job["stage"] || "test").to_s
          jobs << job_reference(job_name, pipeline) if pipeline.stages.any? && !pipeline.stages.include?(stage)
        end
      end

      workflowless = all_pipelines.select { |pipeline| pipeline.workflow.empty? }
      findings << "#{workflowless.size} pipeline files are missing a workflow section, so execution governance depends only on job-level rules" if workflowless.any?
      findings << "A high number of global variables (#{global_variables}) increases maintenance cost" if global_variables > 15
      findings << "Repeated script blocks across #{duplicate_scripts.size} groups suggest refactoring with extends or anchors" if duplicate_scripts.any?
      findings << "The most complex rule contains #{rule_complexity} logical tokens" if rule_complexity >= 8
      findings << "Long jobs detected: #{long_script_jobs.join(', ')}" if long_script_jobs.any?
      findings << "Deprecated only/except syntax is still used in jobs: #{deprecated_jobs.join(', ')}" if deprecated_jobs.any?
      findings << "Jobs use stages outside the declared stage list: #{undefined_stage_jobs.join(', ')}" if undefined_stage_jobs.any?
      findings << "The pipeline contains #{job_count} active jobs, which raises maintenance cost" if job_count > 12
      findings << "#{unresolved_downstream_references.size} downstream triggers could not be resolved, so full-pipeline analysis is partial" if unresolved_downstream_references.any?

      score = 10
      score -= 2 if workflowless.any?
      score -= 1 if global_variables > 15
      score -= 2 if duplicate_scripts.any?
      score -= 2 if rule_complexity >= 8
      score -= 1 if long_script_jobs.any?
      score -= 1 if deprecated_jobs.any?
      score -= 1 if undefined_stage_jobs.any?
      score -= 1 if job_count > 12
      score -= 1 if unresolved_downstream_references.any?
      score = 0 if score.negative?

      {
        score: score,
        max_score: 10,
        summary: findings.empty? ? "The pipeline is relatively easy to maintain" : findings.first,
        findings: findings,
        duplicate_scripts: duplicate_scripts
      }
    end

    def duplicate_script_groups
      signatures = Hash.new { |hash, key| hash[key] = [] }
      all_pipelines.each do |pipeline|
        pipeline.jobs.each do |job_name, job|
          lines = GitlabCiAuditor.normalize_array(job["script"]).map { |line| line.strip.gsub(/\s+/, " ") }.reject(&:empty?)
          next if lines.size < 2

          signatures[lines.join("\n")] << job_reference(job_name, pipeline)
        end
      end
      signatures.values.select { |group| group.size > 1 }
    end

    def max_rule_complexity
      complexities = []
      all_pipelines.each do |pipeline|
        Array(pipeline.workflow["rules"]).each do |rule|
          complexities << complexity_for_expression(rule["if"]) if rule.is_a?(Hash)
        end
        pipeline.jobs.each_value do |job|
          Array(job["rules"]).each do |rule|
            complexities << complexity_for_expression(rule["if"]) if rule.is_a?(Hash)
          end
        end
      end
      complexities.max || 0
    end

    def complexity_for_expression(expression)
      expression.to_s.scan(/&&|\|\||==|!=|=~|!~|\$[A-Za-z_][A-Za-z0-9_]*/).size
    end

    def collect_long_job_names
      all_pipelines.each_with_object([]) do |pipeline, jobs|
        pipeline.jobs.each do |job_name, job|
          jobs << job_reference(job_name, pipeline) if collect_script_lines(pipeline, job).size > 10
        end
      end
    end

    def collect_artifact_strings(value)
      case value
      when Hash
        value.values.flat_map { |item| collect_artifact_strings(item) }
      when Array
        value.flat_map { |item| collect_artifact_strings(item) }
      when nil
        []
      else
        [value.to_s]
      end
    end

    def jacoco_artifacts?(artifact_strings)
      coverage_report_job?(artifact_strings)
    end

    def explicit_unit_test_command?(text)
      text.match?(/\b(pytest|nosetests|tox|jest|vitest|rspec|phpunit|go test|dotnet test|mvn test|gradle test|npm test|yarn test|pnpm test|cargo test)\b/)
    end

    def maven_command_runs_tests?(line)
      return false unless line.match?(/(?:^|\s)(?:\.\/mvnw|mvn)\b/)
      return false unless line.match?(/\b(test|verify|package|install|deploy)\b/)
      return false if line.match?(/-dskiptests(?:=(?!false\b)[^\s]+)?\b/i)
      return false if line.match?(/-dmaven\.test\.skip(?:=(?!false\b)[^\s]+)?\b/i)

      true
    end

    def gradle_command_runs_tests?(line)
      return false unless line.match?(/(?:^|\s)(?:\.\/gradlew|gradle)\b/)
      return false unless line.match?(/\b(test|build|check)\b/)
      return false if line.match?(/(?:^|\s)-x\s+test(?:\s|$)/)
      return false if line.match?(/--exclude-task(?:=|\s+)test(?:\s|$)/)

      true
    end

    def environment_pattern(names)
      escaped = Array(names).map { |name| Regexp.escape(name) }
      /(#{escaped.join("|")})/i
    end

    def strengths(active_scenarios, security_findings, maintainability)
      items = []
      items << "The pipeline declares an explicit stage list" if effective_stages.any?
      items << "No inline secrets were detected in the variables section" if security_findings.none? { |finding| finding[:title].include?("Sensitive variable") }
      items << "Images are pinned instead of relying on latest" if security_findings.none? { |finding| finding[:title].include?("latest") }
      items << "At least some execution scenarios achieve full SSDLC coverage" if active_scenarios.any? { |scenario| scenario[:status] == "pass" }
      items << "Coverage artifacts are published for supported scenarios" if control_required?(:coverage_report) && active_scenarios.any? { |scenario| scenario[:controls][:coverage_report][:status] == "pass" }
      items << "Local child/downstream pipelines are included in the analysis scope" if resolved_downstream_references.any?
      items << "Pipeline complexity remains under control" if maintainability[:score] >= 7
      items.uniq
    end

    def recommendations(coverage, security_findings, maintainability, inactive_scenarios)
      items = []

      items << "Add a dedicated unit-test job or run tests inside the build job without skip flags and publish JaCoCo evidence" if control_required?(:unit_tests) && coverage[:unit_tests][:missing].positive?
      items << "Publish explicit coverage artifacts such as JaCoCo, Cobertura, or LCOV so coverage reporting is visible per scenario" if control_required?(:coverage_report) && (coverage[:coverage_report][:missing].positive? || coverage[:coverage_report][:warn].positive?)
      items << "Add enforced SAST without allow_failure, ideally through a GitLab template or a dedicated scanner job" if control_required?(:sast) && (coverage[:sast][:missing].positive? || coverage[:sast][:warn].positive?)
      items << "Add artifact scanning or image scanning based on the build type and treat the result as a gate" if control_required?(:scan) && (coverage[:scan][:missing].positive? || coverage[:scan][:warn].positive?)
      items << "Automate deployment to a test environment and declare it explicitly in the environment section" if control_required?(:deploy_test) && (coverage[:deploy_test][:missing].positive? || coverage[:deploy_test][:warn].positive?)
      items << "Add workflow:rules to control centrally when a pipeline should exist" if all_pipelines.any? { |pipeline| pipeline.workflow.empty? }
      items << "Remove allow_failure from critical test and scan jobs" if security_findings.any? { |finding| finding[:title].include?("allow_failure") }
      items << "Remove StrictHostKeyChecking no and replace it with controlled known_hosts management" if security_findings.any? { |finding| finding[:title].include?("Host key verification") || finding[:title].include?("host key") }
      items << "Reduce script duplication with hidden jobs, anchors, or extends" if maintainability[:duplicate_scripts].any?
      items << "Move environment-specific global variables into a configuration file or policy pack" if all_pipelines.sum { |pipeline| pipeline.variables.size } > 15
      items << "Review scenarios blocked by workflow rules if they should remain business-supported paths" if inactive_scenarios.any?
      items << "Provide local child pipelines through `trigger: include: - local:` or export their YAML into the audit input if you want full downstream coverage" if unresolved_downstream_references.any?

      items.uniq
    end

    def effective_stages
      stages = all_pipelines.flat_map(&:stages).uniq
      stages.any? ? stages : %w[build test deploy]
    end

    def build_ssdlc_findings(active_scenarios, coverage, inactive_scenarios)
      findings = []
      findings.concat(control_findings(:unit_tests, active_scenarios, coverage[:unit_tests])) if control_required?(:unit_tests)
      findings.concat(control_findings(:coverage_report, active_scenarios, coverage[:coverage_report])) if control_required?(:coverage_report)
      findings.concat(control_findings(:sast, active_scenarios, coverage[:sast])) if control_required?(:sast)
      findings.concat(control_findings(:scan, active_scenarios, coverage[:scan])) if control_required?(:scan)
      findings.concat(control_findings(:deploy_test, active_scenarios, coverage[:deploy_test])) if control_required?(:deploy_test)

      if unresolved_downstream_references.any?
        findings << {
          severity: "medium",
          title: "Downstream pipeline analysis is partial",
          issue: "#{unresolved_downstream_references.size} child or downstream triggers were detected that cannot be loaded statically from the local repository.",
          recommendation: "Prefer local child pipelines or provide their YAML to the auditor.",
          how_to_fix: "Prefer `trigger: include: - local: child.yml` for pipelines in the same repository. For artifact-generated or multi-project pipelines, add a separate configuration export for the scanner.",
          evidence: unresolved_downstream_references.map { |reference| "#{reference.trigger_job_name}: #{reference.warning}" }.first(5)
        }
      end

      if inactive_scenarios.any?
        findings << {
          severity: "low",
          title: "Some scenarios are blocked by workflow rules",
          issue: "#{inactive_scenarios.size} scenarios do not create a pipeline because of `workflow:rules` or inherited control rules.",
          recommendation: "Verify whether this behavior is intentional and whether it hides SSDLC blind spots.",
          how_to_fix: "If a branch or source should be supported, add explicit `workflow:rules` and matching quality or security job rules.",
          evidence: inactive_scenarios.first(5).map { |scenario| scenario[:label] }
        }
      end

      findings
    end

    def control_findings(control_key, active_scenarios, status_counts)
      status = overall_control_status(status_counts)
      return [] if status == "pass"

      guidance = control_guidance.fetch(control_key)
      failing_scenarios = active_scenarios.select { |scenario| scenario[:controls][control_key][:status] != "pass" }
      failing_evidence = failing_scenarios.first(5).map do |scenario|
        evidence = scenario[:controls][control_key][:evidence]
        evidence.any? ? "#{scenario[:label]} -> #{evidence.join(', ')}" : scenario[:label]
      end

      [{
        severity: status == "fail" ? "high" : "medium",
        title: guidance[:title],
        issue: guidance[:issue].call(status_counts, active_scenarios.size),
        recommendation: guidance[:recommendation],
        how_to_fix: guidance[:how_to_fix],
        evidence: failing_evidence
      }]
    end

    def overall_control_status(status_counts)
      return "fail" if status_counts[:missing].positive?
      return "warn" if status_counts[:warn].positive?

      "pass"
    end

    def normalized_policy_meta
      meta = @policy["meta"].is_a?(Hash) ? @policy["meta"] : {}
      {
        name: meta["name"] || "custom",
        label: meta["label"] || meta["name"] || "Custom Policy",
        source: meta["source"] || "custom"
      }
    end

    def control_guidance
      {
        unit_tests: {
          title: "Unit test gate is not complete",
          issue: lambda { |counts, total|
            "#{counts[:missing]}/#{total} scenarios do not show unit test execution, and #{counts[:warn]} scenarios only run tests in a non-enforcing context."
          },
          recommendation: "Enforce unit test execution across every supported pipeline path.",
          how_to_fix: "Add a `unit_tests` job or run tests through `mvn verify|package|install` or `./gradlew build|check` without skip flags. Keep `allow_failure` disabled so the result acts as a gate."
        },
        coverage_report: {
          title: "Coverage reporting is not complete",
          issue: lambda { |counts, total|
            "#{counts[:missing]}/#{total} scenarios do not publish test coverage artifacts, and #{counts[:warn]} scenarios only publish them in a non-enforcing context."
          },
          recommendation: "Publish explicit coverage artifacts independently from test execution detection.",
          how_to_fix: "Generate and publish coverage outputs such as `jacoco.exec`, `jacoco.xml`, `cobertura-coverage.xml`, or `lcov.info` in job artifacts so the auditor can distinguish coverage reporting from plain test execution."
        },
        sast: {
          title: "SAST gate is not complete",
          issue: lambda { |counts, total|
            "#{counts[:missing]}/#{total} scenarios have no SAST, and #{counts[:warn]} scenarios run SAST in a non-enforcing mode."
          },
          recommendation: "Add a mandatory SAST stage for every supported branch and merge request path.",
          how_to_fix: "The simplest option is `include: - template: Jobs/SAST.gitlab-ci.yml`, or add a job using `semgrep`, `sonar-scanner`, or another scanner and remove `allow_failure`."
        },
        scan: {
          title: "Artifact or image scanning is not complete",
          issue: lambda { |counts, total|
            "#{counts[:missing]}/#{total} scenarios have no artifact or image scan, and #{counts[:warn]} scenarios run the scan in a non-enforcing mode."
          },
          recommendation: "Add a mandatory dependency, artifact, or image scan after build output is produced.",
          how_to_fix: "For application or source scans, use tools such as `trivy fs`, `dependency-check`, or `grype`. For container images, add `trivy image` after image build and treat the exit code as a gate."
        },
        deploy_test: {
          title: "Automated test deployment is not complete",
          issue: lambda { |counts, total|
            "#{counts[:missing]}/#{total} scenarios do not deploy automatically to a test environment, and #{counts[:warn]} scenarios do so in a non-enforcing way."
          },
          recommendation: "Deploy automatically to a test environment after tests and scans succeed.",
          how_to_fix: "Add a job with `environment: name: test|qa|staging`, `when: on_success`, and `needs` from build, test, and scan jobs. Avoid `when: manual` for the test environment when SSDLC policy expects continuous validation."
        }
      }
    end

    def build_pipeline_graph
      pipelines = all_pipelines
      stages = effective_stages
      stage_index = stages.each_with_index.to_h
      nodes = []
      edges = []
      node_index = {}

      pipelines.each_with_index do |pipeline, pipeline_idx|
        pipeline.jobs.each do |job_name, job|
          node = build_graph_node(pipeline, pipeline_idx, job_name, job, stage_index)
          nodes << node
          node_index[[pipeline.path, job_name]] = node
        end
      end

      pipelines.each do |pipeline|
        pipeline.jobs.each do |job_name, job|
          from_id = graph_node_id(pipeline, job_name)

          job_needs(job).each do |need_name|
            next unless node_index[[pipeline.path, need_name]]

            edges << {
              from: graph_node_id(pipeline, need_name),
              to: from_id,
              type: "needs"
            }
          end

          pipeline.downstream_references.select { |reference| reference.trigger_job_name == job_name && reference.pipeline }.each do |reference|
            child_roots(reference.pipeline).each do |child_job_name|
              edges << {
                from: from_id,
                to: graph_node_id(reference.pipeline, child_job_name),
                type: "trigger"
              }
            end
          end
        end
      end

      {
        stages: stages,
        pipelines: pipelines.map.with_index do |pipeline, idx|
          {
            label: relative_pipeline_path(pipeline.path),
            order: idx
          }
        end,
        nodes: nodes.sort_by { |node| [node[:stage_index], node[:pipeline_index], node[:label]] },
        edges: edges.uniq
      }
    end

    def build_graph_node(pipeline, pipeline_idx, job_name, job, stage_index)
      script_lines = collect_script_lines(pipeline, job)
      artifact_strings = collect_artifact_strings(job["artifacts"])
      environment_name = extract_environment_name(job)
      classifications = classify_job(job_name, job, script_lines, artifact_strings, environment_name)
      trigger_refs = pipeline.downstream_references.select { |reference| reference.trigger_job_name == job_name }
      strengths = graph_job_strengths(pipeline, job_name, job, script_lines, artifact_strings, environment_name, classifications, trigger_refs)
      weaknesses = graph_job_weaknesses(pipeline, job_name, job, script_lines, artifact_strings, environment_name, classifications, trigger_refs)
      stage = (job["stage"] || "test").to_s

      {
        id: graph_node_id(pipeline, job_name),
        label: job_name,
        stage: stage,
        stage_index: stage_index.fetch(stage, stage_index.size),
        pipeline_label: relative_pipeline_path(pipeline.path),
        pipeline_index: pipeline_idx,
        classifications: classifications,
        strengths: strengths,
        weaknesses: weaknesses,
        variant: graph_node_variant(strengths, weaknesses, classifications, trigger_refs),
        when: (job["when"] || "on_success").to_s,
        manual: job["when"].to_s == "manual",
        allow_failure: job["allow_failure"] == true,
        environment: environment_name,
        needs: job_needs(job),
        has_trigger: trigger_refs.any?,
        unresolved_downstream: trigger_refs.any? { |reference| reference.pipeline.nil? },
        notes: graph_job_notes(job, artifact_strings, script_lines)
      }
    end

    def graph_node_id(pipeline, job_name)
      "#{relative_pipeline_path(pipeline.path)}::#{job_name}"
    end

    def job_needs(job)
      Array(job["needs"]).map do |need|
        case need
        when String
          need
        when Hash
          need["job"] || need[:job]
        end
      end.compact
    end

    def child_roots(pipeline)
      stage_order = pipeline.stages.any? ? pipeline.stages : pipeline.jobs.values.map { |job| (job["stage"] || "test").to_s }.uniq
      first_stage = stage_order.first || "test"
      pipeline.jobs.select { |_name, job| (job["stage"] || "test").to_s == first_stage }.keys
    end

    def graph_job_strengths(pipeline, job_name, job, script_lines, artifact_strings, environment_name, classifications, trigger_refs)
      items = []
      items << "Runs unit tests" if classifications.include?("unit_tests")
      items << "Publishes coverage evidence" if classifications.include?("coverage_report")
      items << "Provides SAST coverage" if classifications.include?("sast")
      items << "Scans artifacts or dependencies" if classifications.include?("artifact_scan")
      items << "Scans container images" if classifications.include?("image_scan")
      items << "Deploys automatically to a test environment" if classifications.include?("deploy_test") && job["when"].to_s != "manual"
      items << "Declares explicit needs dependencies" if job_needs(job).any?
      items << "Orchestrates a local child/downstream pipeline" if trigger_refs.any? { |reference| reference.pipeline }

      image_name = extract_image_name(job["image"] || pipeline.raw_config["image"])
      if image_name && !image_name.empty? && !image_name.include?(":latest") && (image_name.include?(":") || image_name.include?("@sha256:"))
        items << "Uses a pinned image"
      end

      items.uniq
    end

    def graph_job_weaknesses(pipeline, job_name, job, script_lines, artifact_strings, environment_name, classifications, trigger_refs)
      items = []

      critical_gate = (classifications & %w[unit_tests sast artifact_scan image_scan deploy_test]).any?
      items << "Critical gate is optional because allow_failure is enabled" if critical_gate && job["allow_failure"] == true
      items << "Test deployment is manual" if classifications.include?("deploy_test") && job["when"].to_s == "manual"
      items << "Triggers downstream content outside the analysis scope" if trigger_refs.any? { |reference| reference.pipeline.nil? }
      items << "Disables Maven tests through skip flags" if script_lines.any? { |line| line.downcase.match?(/-dskiptests(?:=(?!false\b)[^\s]+)?\b| -dmaven\.test\.skip/i) }
      items << "Disables Gradle tests through -x test" if script_lines.any? { |line| line.downcase.match?(/(?:^|\s)-x\s+test(?:\s|$)|--exclude-task(?:=|\s+)test(?:\s|$)/) }
      items << "Uses a latest image tag" if (image_name = extract_image_name(job["image"] || pipeline.raw_config["image"])) && image_name.include?(":latest")
      items << "Image has no explicit tag" if image_name && !image_name.empty? && !image_name.include?(":") && !image_name.include?("@sha256:")
      items << "Does not contribute a direct SSDLC control" if critical_gate == false && trigger_refs.empty?
      items.uniq
    end

    def graph_node_variant(strengths, weaknesses, classifications, trigger_refs)
      return "risk" if weaknesses.any? && strengths.empty?
      return "mixed" if weaknesses.any? && strengths.any?
      return "trigger" if trigger_refs.any?
      return "good" if strengths.any?
      return "neutral"
    end

    def graph_job_notes(job, artifact_strings, script_lines)
      notes = []
      notes << "Artifacts: #{artifact_strings.first(4).join(', ')}" if artifact_strings.any?
      notes << "Environment: #{extract_environment_name(job)}" if extract_environment_name(job)
      notes << "Script lines: #{script_lines.size}"
      notes
    end

    def all_pipelines(pipeline = @pipeline, seen = {})
      return [] if seen[pipeline.object_id]

      seen[pipeline.object_id] = true
      [pipeline] + pipeline.downstream_references.flat_map do |reference|
        next [] unless reference.pipeline

        all_pipelines(reference.pipeline, seen)
      end
    end

    def resolved_downstream_references
      all_pipelines.flat_map(&:downstream_references).select { |reference| reference.pipeline }
    end

    def unresolved_downstream_references
      all_pipelines.flat_map(&:downstream_references).reject { |reference| reference.pipeline }
    end

    def aggregate_loader_warnings
      all_pipelines.flat_map(&:warnings).uniq
    end

    def total_job_count
      all_pipelines.sum { |pipeline| pipeline.jobs.size }
    end

    def relative_pipeline_path(path)
      path.sub(%r{\A#{Regexp.escape(Dir.pwd)}/?}, "")
    end

    def job_reference(job_name, pipeline)
      "#{job_name} [#{relative_pipeline_path(pipeline.path)}]"
    end

    def finding(severity, title, issue, recommendation = nil, how_to_fix = nil, evidence = [])
      {
        severity: severity,
        title: title,
        issue: issue,
        recommendation: recommendation,
        how_to_fix: how_to_fix,
        evidence: Array(evidence)
      }
    end

    def grade_for(score)
      return "A" if score >= 85
      return "B" if score >= 70
      return "C" if score >= 55
      return "D" if score >= 40

      "F"
    end

    def status_for_score(score)
      return "strong" if score >= 85
      return "acceptable" if score >= 70
      return "at_risk" if score >= 55

      "critical"
    end
  end
end
