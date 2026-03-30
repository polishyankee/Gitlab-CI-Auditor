module GitlabCiAuditor
  class Analyzer
    DEFAULT_POLICY = GitlabCiAuditor::PolicyLoader.load
    CONTROL_KEYS = %i[unit_tests coverage_report sast scan deploy_test].freeze
    STACK_LABELS = {
      "dotnet" => ".NET",
      "node_js" => "Node / JS",
      "java" => "Java",
      "python" => "Python",
      "go" => "Go",
      "ruby" => "Ruby",
      "php" => "PHP"
    }.freeze
    TOOL_LABELS = {
      "semgrep" => "semgrep",
      "codeql" => "CodeQL",
      "sonar_scanner" => "SonarQube / sonar-scanner",
      "dotnet_sonarscanner" => "dotnet sonarscanner",
      "security_code_scan" => "Security Code Scan",
      "snyk_code" => "snyk code test",
      "njsscan" => "njsscan",
      "nodejsscan" => "nodejsscan",
      "spotbugs" => "spotbugs",
      "findsecbugs" => "findsecbugs",
      "bandit" => "bandit",
      "gosec" => "gosec",
      "brakeman" => "brakeman",
      "psalm_taint" => "psalm --taint-analysis",
      "progpilot" => "progpilot",
      "horusec" => "horusec",
      "fortify" => "Fortify",
      "coverity" => "Coverity",
      "checkmarx" => "Checkmarx",
      "veracode" => "Veracode",
      "dependency_scanning" => "GitLab Dependency Scanning",
      "dependency_check" => "OWASP Dependency-Check",
      "trivy_fs" => "trivy fs",
      "grype" => "grype",
      "snyk_test" => "snyk test",
      "license_scanning" => "GitLab License Scanning",
      "container_scanning" => "GitLab Container Scanning",
      "trivy_image" => "trivy image",
      "docker_scan" => "docker scan",
      "snyk_container" => "snyk container",
      "anchore" => "Anchore",
      "vault" => "HashiCorp Vault",
      "aws_secretsmanager" => "AWS Secrets Manager",
      "azure_keyvault" => "Azure Key Vault",
      "gcp_secret_manager" => "Google Secret Manager",
      "onepassword" => "1Password",
      "doppler" => "Doppler",
      "sops" => "sops",
      "cosign_sign" => "cosign sign",
      "notation_sign" => "notation sign",
      "gpg_sign" => "gpg signing",
      "checksum_generate" => "checksum generation",
      "cosign_verify" => "cosign verify",
      "notation_verify" => "notation verify",
      "slsa_verifier" => "slsa-verifier",
      "checksum_verify" => "checksum verification",
      "gpg_verify" => "gpg --verify",
      "helm_verify" => "helm verify"
    }.freeze
    SAST_TOOL_PATTERNS = {
      "semgrep" => /\bsemgrep\b/,
      "codeql" => /\bcodeql\b/,
      "sonar_scanner" => /\b(sonarqube|sonar-scanner|sonarscanner|sonarcloud)\b|\bsonar:sonar\b/,
      "dotnet_sonarscanner" => /\b(dotnet\s+sonarscanner|dotnet-sonarscanner|sonarscanner\.msbuild\.exe)\b/,
      "security_code_scan" => /\bsecurity[- ]code[- ]scan\b/,
      "snyk_code" => /\bsnyk\s+code\s+test\b/,
      "njsscan" => /\bnjsscan\b/,
      "nodejsscan" => /\bnodejsscan\b/,
      "spotbugs" => /\bspotbugs\b/,
      "findsecbugs" => /\bfindsecbugs\b/,
      "bandit" => /\bbandit\b/,
      "gosec" => /\bgosec\b/,
      "brakeman" => /\bbrakeman\b/,
      "psalm_taint" => /\bpsalm\b.*\btaint-analysis\b|\btaint-analysis\b.*\bpsalm\b/,
      "progpilot" => /\bprogpilot\b/,
      "horusec" => /\bhorusec\b/,
      "fortify" => /\bfortify\b/,
      "coverity" => /\bcoverity\b/,
      "checkmarx" => /\bcheckmarx\b/,
      "veracode" => /\bveracode\b/
    }.freeze
    ARTIFACT_SCAN_TOOL_PATTERNS = {
      "dependency_scanning" => /\bdependency[- ]scanning\b/,
      "dependency_check" => /\bdependency-check\b|\bowasp\b/,
      "trivy_fs" => /\btrivy\s+fs\b/,
      "grype" => /\bgrype\b/,
      "snyk_test" => /\bsnyk\s+test\b/,
      "license_scanning" => /\blicense[- ]scanning\b/
    }.freeze
    IMAGE_SCAN_TOOL_PATTERNS = {
      "container_scanning" => /\bcontainer[- ]scanning\b/,
      "trivy_image" => /\btrivy\s+image\b/,
      "grype" => /\bgrype\b/,
      "docker_scan" => /\bdocker\s+scan\b/,
      "snyk_container" => /\bsnyk\s+container\b/,
      "anchore" => /\banchore\b/
    }.freeze
    SECRET_MANAGEMENT_PATTERNS = {
      "vault" => /\bvault\b/,
      "aws_secretsmanager" => /\baws\s+secretsmanager\b/,
      "azure_keyvault" => /\baz\s+keyvault\b|\bazure\s+key\s+vault\b/,
      "gcp_secret_manager" => /\bgcloud\s+secrets\b|\bsecretmanager\b/,
      "onepassword" => /\bop\s+read\b|\b1password\b/,
      "doppler" => /\bdoppler\b/,
      "sops" => /\bsops\b/
    }.freeze
    ARTIFACT_SIGNING_PATTERNS = {
      "cosign_sign" => /\bcosign\s+sign(?:-blob)?\b/,
      "notation_sign" => /\bnotation\s+sign\b/,
      "gpg_sign" => /\bgpg\s+--detach-sign\b|\bgpg\s+--sign\b/,
      "checksum_generate" => /\bsha256sum\b(?!\s+-c\b)|\bshasum\s+-a\s+256\b(?!\s+-c\b)|\bopenssl\s+dgst\s+-sha256\b/
    }.freeze
    DEPLOY_INTEGRITY_PATTERNS = {
      "cosign_verify" => /\bcosign\s+verify(?:-attestation)?\b/,
      "notation_verify" => /\bnotation\s+verify\b/,
      "slsa_verifier" => /\bslsa-verifier\b/,
      "checksum_verify" => /\bsha256sum\s+-c\b|\bshasum\s+-a\s+256\s+-c\b/,
      "gpg_verify" => /\bgpg\s+--verify\b/,
      "helm_verify" => /\bhelm\s+verify\b/
    }.freeze
    REPORT_ARTIFACT_PATTERNS = {
      "junit" => /\bjunit\b|surefire-reports\/.*\.xml|test-results\/.*\.xml/,
      "coverage_report" => /jacoco(?:\.exec|\.xml)?|site\/jacoco|jacoco\/.*\.xml|cobertura(?:-coverage)?\.xml|lcov\.info|coverage\/.*\.(xml|exec|info)/,
      "sast_report" => /\bgl-sast-report\.json\b|\bsast.*\.sarif\b|\bcodeql.*\.sarif\b|\bsemgrep.*\.sarif\b|\bsarif\b/,
      "dependency_scanning_report" => /\bgl-dependency-scanning-report\.json\b|\bdependency[-_ ]scanning.*\.json\b|\bdependency-check-report\.(json|xml|html)\b|\bcyclonedx.*\.(json|xml)\b|\bsbom\b/,
      "container_scanning_report" => /\bgl-container-scanning-report\.json\b|\bcontainer[-_ ]scanning.*\.json\b|\btrivy.*\.json\b|\bgrype.*\.json\b/
    }.freeze
    SHELL_SCRIPT_EXTENSIONS = %w[.sh .bash .zsh .ksh].freeze
    SHELL_SCRIPT_COMMANDS = %w[bash sh source .].freeze
    MAX_SCRIPT_EVIDENCE_FILES = 12
    MAX_SCRIPT_EVIDENCE_DEPTH = 4
    DEFAULT_STACK_SAST_REQUIREMENTS = {
      "dotnet" => {
        "label" => ".NET",
        "accepted_families" => %w[semgrep codeql sonar_scanner dotnet_sonarscanner security_code_scan snyk_code horusec fortify coverity checkmarx veracode]
      },
      "node_js" => {
        "label" => "Node / JS",
        "accepted_families" => %w[semgrep codeql sonar_scanner njsscan nodejsscan snyk_code horusec fortify coverity checkmarx veracode]
      },
      "java" => {
        "label" => "Java",
        "accepted_families" => %w[semgrep codeql sonar_scanner spotbugs findsecbugs snyk_code horusec fortify coverity checkmarx veracode]
      },
      "python" => {
        "label" => "Python",
        "accepted_families" => %w[semgrep codeql sonar_scanner bandit snyk_code horusec fortify coverity checkmarx veracode]
      },
      "go" => {
        "label" => "Go",
        "accepted_families" => %w[semgrep codeql gosec snyk_code horusec fortify coverity checkmarx veracode]
      },
      "ruby" => {
        "label" => "Ruby",
        "accepted_families" => %w[semgrep codeql brakeman snyk_code horusec fortify coverity checkmarx veracode]
      },
      "php" => {
        "label" => "PHP",
        "accepted_families" => %w[semgrep codeql psalm_taint progpilot snyk_code horusec fortify coverity checkmarx veracode]
      }
    }.freeze
    OWASP_SAMM_REFERENCES = {
      "secure_build" => "https://owaspsamm.org/model/implementation/secure-build/",
      "secure_deployment" => "https://owaspsamm.org/model/implementation/secure-deployment/",
      "defect_management" => "https://owaspsamm.org/model/implementation/defect-management/"
    }.freeze
    IMPLEMENTATION_QUESTION_CATALOG = YAML.load_file(
      File.join(GitlabCiAuditor.root_dir, "config", "owasp_samm", "implementation_questions.yml")
    ).freeze

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
      @detected_stacks = detect_stacks
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
      benchmarks = build_benchmarks(active_scenarios, coverage, security_findings)
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
        pipeline_path: relative_pipeline_path(@pipeline.path),
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
        benchmarks: benchmarks,
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
          detected_stacks: detected_stack_labels,
          detected_security_tools: detected_security_tools,
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
      sast_stack_coverage = scenario_sast_stack_coverage(active_jobs)

      controls = scenario_controls(active_jobs, sast_stack_coverage)
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
        sast_stack_coverage: sast_stack_coverage,
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
      script_evidence = expand_local_script_evidence(pipeline, script_lines)
      environment_name = extract_environment_name(job)
      image_name = extract_image_name(job["image"] || pipeline.raw_config["image"])
      artifact_strings = collect_artifact_strings(job["artifacts"])
      classifications = classify_job(job_name, job, script_lines, artifact_strings, environment_name, script_evidence)
      text = classification_text(job_name, job, script_lines, artifact_strings, environment_name, script_evidence)
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
        script_evidence_files: script_evidence[:files],
        classifications: classifications,
        sast_tools: detect_sast_tools(text),
        artifact_scan_tools: detect_artifact_scan_tools(text),
        image_scan_tools: detect_image_scan_tools(text),
        secret_management_tools: detect_secret_management_tools(text),
        artifact_signing_tools: detect_artifact_signing_tools(text),
        integrity_verification_tools: detect_integrity_verification_tools(text),
        report_families: detect_report_families(artifact_strings),
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

    def expand_local_script_evidence(pipeline, script_lines, origin_path = nil, depth = 0, visited = {})
      return { lines: [], files: [] } if depth >= MAX_SCRIPT_EVIDENCE_DEPTH

      base_dir = origin_path ? File.dirname(origin_path) : pipeline.base_dir
      files = []
      lines = []

      extract_local_script_paths(script_lines, pipeline, base_dir).each do |script_path|
        next unless script_path
        next if visited[script_path]
        next unless File.file?(script_path)

        visited[script_path] = true
        files << relative_pipeline_asset_path(script_path, pipeline)

        content_lines = File.readlines(script_path, chomp: true).map(&:strip).reject(&:empty?)
        lines.concat(content_lines)

        nested = expand_local_script_evidence(pipeline, content_lines, script_path, depth + 1, visited)
        files.concat(nested[:files])
        lines.concat(nested[:lines])
        break if visited.size >= MAX_SCRIPT_EVIDENCE_FILES
      end

      {
        lines: lines.uniq,
        files: files.uniq
      }
    end

    def extract_local_script_paths(script_lines, pipeline, base_dir)
      Array(script_lines).flat_map do |line|
        extract_local_script_candidates(line).map do |candidate|
          resolve_local_script_path(candidate, pipeline, base_dir)
        end
      end.compact.uniq
    end

    def extract_local_script_candidates(line)
      line.to_s.split(/&&|\|\||;/).flat_map do |segment|
        tokens = Shellwords.split(segment.to_s)
        next [] if tokens.empty?

        if SHELL_SCRIPT_COMMANDS.include?(tokens[0]) && tokens[1]
          [tokens[1]]
        elsif local_script_token?(tokens[0])
          [tokens[0]]
        else
          []
        end
      rescue ArgumentError
        []
      end
    end

    def local_script_token?(token)
      value = token.to_s.strip
      return false if value.empty? || value.include?("$") || value.include?("://")

      extension = File.extname(value).downcase
      SHELL_SCRIPT_EXTENSIONS.include?(extension)
    end

    def resolve_local_script_path(candidate, pipeline, base_dir)
      value = candidate.to_s.strip.delete_prefix("'").delete_prefix('"').delete_suffix("'").delete_suffix('"')
      return nil if value.empty? || value.include?("$")

      if value.start_with?("/")
        return value if File.file?(value)
        return nil
      end

      search_dir = base_dir.to_s.empty? ? pipeline.base_dir : base_dir
      loop do
        resolved = File.expand_path(value, search_dir)
        return resolved if File.file?(resolved)

        parent = File.dirname(search_dir)
        break if parent == search_dir

        search_dir = parent
      end

      nil
    end

    def relative_pipeline_asset_path(path, pipeline)
      relative_to_workspace = relative_pipeline_path(path)
      return relative_to_workspace unless relative_to_workspace == path.to_s

      base_dir = File.expand_path(pipeline.base_dir.to_s)
      expanded = File.expand_path(path.to_s)
      return expanded unless expanded.start_with?("#{base_dir}/")

      expanded.delete_prefix("#{base_dir}/")
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

    def classify_job(job_name, job, script_lines, artifact_strings, environment_name, script_evidence = nil)
      text = classification_text(job_name, job, script_lines, artifact_strings, environment_name, script_evidence)

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

    def classification_text(job_name, job, script_lines, artifact_strings, environment_name, script_evidence = nil)
      evidence = script_evidence || expand_local_script_evidence(@pipeline, script_lines)
      [
        job_name,
        job["stage"],
        environment_name,
        extract_image_name(job["image"]),
        artifact_strings.join("\n"),
        script_lines.join("\n"),
        evidence[:files].join("\n"),
        evidence[:lines].join("\n")
      ].compact.join("\n").downcase
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
      detect_sast_tools(text).any?
    end

    def artifact_scan_job?(text)
      detect_artifact_scan_tools(text).any?
    end

    def image_scan_job?(text)
      detect_image_scan_tools(text).any?
    end

    def deploy_test_job?(text, environment_name)
      deployment_like = text.match?(/\b(deploy|kubectl apply|helm upgrade|ansible-playbook|terraform apply|oc apply|scp |rsync |argocd app (?:sync|wait|create|set|rollback)|argocd appset|argocd app delete)\b/)
      non_prod_env = environment_name.to_s.match?(environment_pattern(@policy["test_environments"]))
      deployment_like && non_prod_env
    end

    def deploy_production_job?(environment_name)
      environment_name.to_s.match?(environment_pattern(@policy["production_environments"]))
    end

    def scenario_controls(active_jobs, sast_stack_coverage = nil)
      controls = {
        unit_tests: control_required?(:unit_tests) ? control_state_for(active_jobs, "unit_tests") : disabled_control("Disabled by the selected policy pack"),
        coverage_report: control_required?(:coverage_report) ? control_state_for(active_jobs, "coverage_report") : disabled_control("Disabled by the selected policy pack"),
        sast: control_required?(:sast) ? sast_control_state(active_jobs, sast_stack_coverage || scenario_sast_stack_coverage(active_jobs)) : disabled_control("Disabled by the selected policy pack"),
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

    def sast_control_state(active_jobs, stack_coverage)
      matching = active_jobs.select { |job| job[:classifications].include?("sast") }
      return missing_control if matching.empty?

      enforced = matching.reject { |job| job[:manual] || job[:allow_failure] }
      evidence = (enforced.any? ? enforced : matching).map { |job| "#{job[:name]} (#{job[:stage]})" }
      evidence.concat(sast_gap_messages(stack_coverage)) if stack_coverage[:missing_stacks].any?

      return warn_control(evidence.uniq) if enforced.empty?
      return warn_control(evidence.uniq) if stack_coverage[:missing_stacks].any?

      pass_control(evidence.uniq)
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
            extract_environment_name(job),
            expand_local_script_evidence(pipeline, script_lines)
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

    def detect_tool_families(patterns, text)
      patterns.each_with_object([]) do |(family, pattern), detected|
        detected << family if pattern.match?(text)
      end
    end

    def detect_sast_tools(text)
      detect_tool_families(SAST_TOOL_PATTERNS, text)
    end

    def detect_artifact_scan_tools(text)
      detect_tool_families(ARTIFACT_SCAN_TOOL_PATTERNS, text)
    end

    def detect_image_scan_tools(text)
      detect_tool_families(IMAGE_SCAN_TOOL_PATTERNS, text)
    end

    def detect_secret_management_tools(text)
      detect_tool_families(SECRET_MANAGEMENT_PATTERNS, text)
    end

    def detect_artifact_signing_tools(text)
      detect_tool_families(ARTIFACT_SIGNING_PATTERNS, text)
    end

    def detect_integrity_verification_tools(text)
      detect_tool_families(DEPLOY_INTEGRITY_PATTERNS, text)
    end

    def detect_report_families(artifact_strings)
      text = artifact_strings.join("\n").downcase
      detect_tool_families(REPORT_ARTIFACT_PATTERNS, text)
    end

    def normalized_stack_sast_requirements
      @normalized_stack_sast_requirements ||= DEFAULT_STACK_SAST_REQUIREMENTS.each_with_object({}) do |(stack_key, defaults), requirements|
        override = @policy.fetch("stack_sast_requirements", {}).fetch(stack_key, {})
        accepted_families = Array(override["accepted_families"])
        requirements[stack_key] = {
          "label" => override["label"] || defaults["label"] || STACK_LABELS.fetch(stack_key, stack_key),
          "accepted_families" => accepted_families.empty? ? defaults["accepted_families"] : accepted_families
        }
      end
    end

    def scenario_sast_stack_coverage(active_jobs)
      active_tools = active_jobs.flat_map { |job| Array(job[:sast_tools]) }.uniq
      covered_stacks = []
      missing_stacks = []
      matched_tools = {}

      @detected_stacks.each do |stack_key|
        requirement = normalized_stack_sast_requirements[stack_key]
        next unless requirement

        matches = active_tools & Array(requirement["accepted_families"])
        if matches.any?
          covered_stacks << stack_key
          matched_tools[stack_key] = matches
        else
          missing_stacks << stack_key
        end
      end

      {
        active_tools: active_tools,
        covered_stacks: covered_stacks,
        missing_stacks: missing_stacks,
        matched_tools: matched_tools
      }
    end

    def sast_gap_messages(stack_coverage)
      stack_coverage[:missing_stacks].map do |stack_key|
        requirement = normalized_stack_sast_requirements[stack_key]
        accepted = Array(requirement["accepted_families"]).map { |family| tool_family_label(family) }
        "Detected #{requirement['label']} but no accepted stack-specific SAST tool is active. Accepted families: #{accepted.join(', ')}"
      end
    end

    def detected_security_tools
      jobs = all_pipelines.flat_map do |pipeline|
        pipeline.jobs.map do |job_name, job|
          script_lines = collect_script_lines(pipeline, job)
          artifact_strings = collect_artifact_strings(job["artifacts"])
          environment_name = extract_environment_name(job)
          text = classification_text(
            job_name,
            job,
            script_lines,
            artifact_strings,
            environment_name,
            expand_local_script_evidence(pipeline, script_lines)
          )
          {
            sast: detect_sast_tools(text),
            artifact_scan: detect_artifact_scan_tools(text),
            image_scan: detect_image_scan_tools(text),
            secret_management: detect_secret_management_tools(text),
            integrity_verification: detect_integrity_verification_tools(text)
          }
        end
      end

      {
        sast: jobs.flat_map { |job| job[:sast] }.uniq.map { |family| tool_family_label(family) },
        artifact_scan: jobs.flat_map { |job| job[:artifact_scan] }.uniq.map { |family| tool_family_label(family) },
        image_scan: jobs.flat_map { |job| job[:image_scan] }.uniq.map { |family| tool_family_label(family) },
        secret_management: jobs.flat_map { |job| job[:secret_management] }.uniq.map { |family| tool_family_label(family) },
        integrity_verification: jobs.flat_map { |job| job[:integrity_verification] }.uniq.map { |family| tool_family_label(family) }
      }
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
      items << "If deployment is executed from a separate ArgoCD or delivery repository, analyze that repository too through a downstream snapshot or a separate auditor run" if control_required?(:deploy_test) && coverage[:deploy_test][:missing].positive?
      items << "Add workflow:rules to control centrally when a pipeline should exist" if all_pipelines.any? { |pipeline| pipeline.workflow.empty? }
      items << "Remove allow_failure from critical test and scan jobs" if security_findings.any? { |finding| finding[:title].include?("allow_failure") }
      items << "Remove StrictHostKeyChecking no and replace it with controlled known_hosts management" if security_findings.any? { |finding| finding[:title].include?("Host key verification") || finding[:title].include?("host key") }
      items << "Reduce script duplication with hidden jobs, anchors, or extends" if maintainability[:duplicate_scripts].any?
      items << "Move environment-specific global variables into a configuration file or policy pack" if all_pipelines.sum { |pipeline| pipeline.variables.size } > 15
      items << "Review scenarios blocked by workflow rules if they should remain business-supported paths" if inactive_scenarios.any?
      items << "Provide local child pipelines through `trigger: include: - local:` or export their YAML into the audit input if you want full downstream coverage" if unresolved_downstream_references.any?

      items.uniq
    end

    def build_benchmarks(active_scenarios, coverage, security_findings)
      {
        owasp_samm_v2: build_owasp_samm_v2_benchmark(active_scenarios, coverage, security_findings)
      }
    end

    def build_owasp_samm_v2_benchmark(active_scenarios, coverage, security_findings)
      jobs = unique_active_jobs(active_scenarios)
      practices = [
        samm_secure_build(jobs, coverage, security_findings),
        samm_secure_deployment(jobs, coverage, security_findings),
        samm_defect_management(jobs, coverage, security_findings)
      ]

      {
        framework: "OWASP SAMM v2",
        scope: "Implementation",
        note: "Pipeline-derived estimate based on static CI/CD evidence. Organizational process evidence outside YAML may increase or decrease the real SAMM maturity.",
        observed_signals: samm_observed_signals(active_scenarios, coverage, jobs, security_findings, practices),
        references: OWASP_SAMM_REFERENCES.map do |key, url|
          { key: key, url: url }
        end,
        practices: practices
      }
    end

    def samm_observed_signals(active_scenarios, coverage, jobs, security_findings, practices = [])
      security_tools = detected_security_tools
      report_families = jobs.flat_map { |job| Array(job[:report_families]) }.uniq
      security_reports = report_families & %w[sast_report dependency_scanning_report container_scanning_report]
      environments = jobs.map { |job| job[:environment] }.compact.uniq
      workflow_governed = all_pipelines.none? { |pipeline| pipeline.workflow.empty? }
      gating = security_findings.none? { |finding| finding[:title].include?("allow_failure") }
      question_summary = benchmark_question_summary(practices.flat_map { |practice| practice[:questions] })

      [
        benchmark_signal_group(
          "analysis_scope",
          "Analysis Scope",
          [
            "Analysis scope: #{unresolved_downstream_references.empty? ? 'complete' : 'partial'}",
            "Pipeline files analyzed: #{all_pipelines.size}",
            "Active scenarios analyzed: #{active_scenarios.size}",
            "Unique active jobs mapped into the benchmark: #{jobs.size}",
            "Resolved downstream pipelines: #{resolved_downstream_references.size}",
            unresolved_downstream_references.any? ? "Unresolved downstream pipelines: #{unresolved_downstream_references.size}" : "No unresolved downstream pipelines detected"
          ]
        ),
        benchmark_signal_group(
          "technology_and_flow",
          "Technology and Flow Signals",
          [
            detected_stack_labels.any? ? "Detected stacks: #{detected_stack_labels.join(', ')}" : "No application stack signal detected from images, scripts, or artifact names",
            "Stage model: #{effective_stages.join(', ')}",
            workflow_governed ? "workflow:rules is present on every analyzed pipeline file" : "At least one analyzed pipeline file has no workflow:rules",
            environments.any? ? "Declared environments: #{environments.join(', ')}" : "No explicit deployment environment detected"
          ]
        ),
        benchmark_signal_group(
          "controls_and_gates",
          "Controls and Gates",
          [
            benchmark_control_signal("Unit test execution", coverage[:unit_tests], active_scenarios.size),
            benchmark_control_signal("Coverage reporting", coverage[:coverage_report], active_scenarios.size),
            benchmark_control_signal("SAST coverage", coverage[:sast], active_scenarios.size),
            benchmark_control_signal("Artifact or image scanning", coverage[:scan], active_scenarios.size),
            benchmark_control_signal("Automated test deployment", coverage[:deploy_test], active_scenarios.size),
            gating ? "Critical quality and security jobs are blocking" : "At least one critical quality or security job is optional because `allow_failure` is enabled"
          ]
        ),
        benchmark_signal_group(
          "security_tooling",
          "Security Tooling",
          [
            benchmark_family_signal("SAST families", security_tools[:sast]),
            benchmark_family_signal("Artifact scan families", security_tools[:artifact_scan]),
            benchmark_family_signal("Image scan families", security_tools[:image_scan]),
            benchmark_family_signal("Secret-management signals", security_tools[:secret_management]),
            benchmark_family_signal("Integrity-verification signals", security_tools[:integrity_verification])
          ]
        ),
        benchmark_signal_group(
          "reports_and_feedback",
          "Reports and Feedback Loops",
          [
            benchmark_family_signal("Report artifacts", report_families.map { |family| tool_family_label(family) }),
            benchmark_family_signal("Security report artifacts", security_reports.map { |family| tool_family_label(family) }),
            security_findings.empty? ? "No policy findings reduced benchmark confidence on the analyzed YAML" : "#{security_findings.size} policy findings reduce benchmark confidence on the analyzed YAML",
            all_pipelines.size > 1 ? "Cross-component scope detected: #{all_pipelines.size} pipeline files analyzed together" : "Cross-component scope is limited to a single pipeline file"
          ]
        ),
        benchmark_signal_group(
          "question_mapping",
          "Upstream Question Mapping",
          [
            "Mapped implementation questions: #{question_summary[:total]}",
            "Question status counts: #{question_summary[:pass]} pass, #{question_summary[:warn]} warn, #{question_summary[:fail]} fail, #{question_summary[:review]} review",
            "Questions that require manual or process evidence: #{question_summary[:review_only]}",
            question_summary[:review_only].positive? ? "Some SAMM questions remain review-oriented because CI/CD YAML cannot prove organizational process maturity on its own" : "All mapped SAMM questions are directly or partially observable from CI/CD evidence"
          ]
        )
      ]
    end

    def benchmark_signal_group(key, label, values)
      {
        key: key,
        label: label,
        values: Array(values).flatten.compact.map(&:to_s).reject(&:empty?).uniq
      }
    end

    def benchmark_control_signal(label, status_counts, active_scenarios_count)
      if active_scenarios_count.zero?
        "#{label}: no active scenarios were created by the current workflow and ruleset"
      else
        "#{label}: #{status_summary(status_counts)} across #{active_scenarios_count} active scenarios"
      end
    end

    def benchmark_family_signal(label, values)
      list = Array(values).flatten.compact.map(&:to_s).reject(&:empty?).uniq
      return "#{label}: #{list.join(', ')}" if list.any?

      "#{label}: none detected"
    end

    def implementation_questions_for(practice_key)
      IMPLEMENTATION_QUESTION_CATALOG.select { |question| question["practice"] == practice_key }
    end

    def assess_implementation_questions(practice_key, context)
      implementation_questions_for(practice_key).map do |question|
        evaluate_implementation_question(question, context)
      end
    end

    def evaluate_implementation_question(question, context)
      result = send("evaluate_question_#{question.fetch('heuristic')}", context)
      {
        key: question.fetch("key"),
        title: question.fetch("title"),
        status: result.fetch(:status),
        observability: question.fetch("observability"),
        detail: result.fetch(:detail),
        recommendation: result[:recommendation],
        static_limitations: question.fetch("static_limitations"),
        source_url: question.fetch("source_url")
      }
    end

    def benchmark_question_summary(questions)
      Array(questions).each_with_object({ total: 0, pass: 0, warn: 0, fail: 0, review: 0, direct: 0, partial: 0, review_only: 0 }) do |question, summary|
        status = question[:status].to_s
        observability = question[:observability].to_s
        summary[:total] += 1
        summary[status.to_sym] += 1 if summary.key?(status.to_sym)
        summary[observability.to_sym] += 1 if summary.key?(observability.to_sym)
        summary[:review_only] += 1 if observability == "review"
      end
    end

    def question_result(status, detail, recommendation = nil)
      {
        status: status,
        detail: detail,
        recommendation: recommendation
      }
    end

    def secure_build_question_context(jobs, coverage, security_findings)
      build_jobs = jobs.reject { |job| deployment_job?(job) }
      report_families = build_jobs.flat_map { |job| Array(job[:report_families]) }.uniq
      dependency_scan_jobs = build_jobs.select { |job| Array(job[:artifact_scan_tools]).any? }

      {
        build_jobs: build_jobs,
        build_manual_jobs: build_jobs.select { |job| job[:manual] },
        stages_present: effective_stages.any?,
        workflow_governed: all_pipelines.none? { |pipeline| pipeline.workflow.empty? },
        unit_ratio: ratio_for(coverage[:unit_tests]),
        coverage_ratio: ratio_for(coverage[:coverage_report]),
        sast_ratio: ratio_for(coverage[:sast]),
        scan_ratio: ratio_for(coverage[:scan]),
        gated: security_findings.none? { |finding| finding[:title].include?("allow_failure") },
        dependency_scan_tools: dependency_scan_jobs.flat_map { |job| Array(job[:artifact_scan_tools]) }.uniq,
        dependency_scan_reports: report_families & %w[dependency_scanning_report],
        sbom_present: build_jobs.any? { |job| Array(job[:artifacts]).join("\n").downcase.match?(/cyclonedx|sbom|spdx/) },
        license_scan_present: build_jobs.any? { |job| Array(job[:artifact_scan_tools]).include?("license_scanning") },
        build_secret_tools: build_jobs.flat_map { |job| Array(job[:secret_management_tools]) }.uniq,
        artifact_signing_tools: build_jobs.flat_map { |job| Array(job[:artifact_signing_tools]) }.uniq,
        dependency_scan_enforced: dependency_scan_jobs.any? { |job| !job[:manual] && !job[:allow_failure] }
      }
    end

    def secure_deployment_question_context(jobs, coverage, security_findings)
      deploy_jobs = jobs.select { |job| deployment_job?(job) }

      {
        deploy_jobs: deploy_jobs,
        manual_deploy_jobs: deploy_jobs.select { |job| job[:manual] },
        environments: deploy_jobs.map { |job| job[:environment] }.compact.uniq,
        deploy_ratio: ratio_for(coverage[:deploy_test]),
        gating: ratio_for(coverage[:unit_tests]) >= 0.45 && ratio_for(coverage[:sast]) >= 0.45 && ratio_for(coverage[:scan]) >= 0.45,
        production_present: jobs.any? { |job| job[:classifications].include?("deploy_prod") },
        secret_management_tools: deploy_jobs.flat_map { |job| Array(job[:secret_management_tools]) }.uniq,
        artifact_signing_tools: jobs.flat_map { |job| Array(job[:artifact_signing_tools]) }.uniq,
        integrity_verification_tools: deploy_jobs.flat_map { |job| Array(job[:integrity_verification_tools]) }.uniq,
        inline_secret_findings: security_findings.select { |finding| finding[:title].include?("Sensitive variable") }
      }
    end

    def defect_management_question_context(jobs, coverage, security_findings)
      report_families = jobs.flat_map { |job| Array(job[:report_families]) }.uniq
      security_reports = report_families & %w[sast_report dependency_scanning_report container_scanning_report]

      {
        structured_reporting: report_families.include?("junit") || report_families.include?("coverage_report"),
        security_reports: security_reports,
        blocking_gates: security_findings.none? { |finding| finding[:title].include?("allow_failure") },
        flow_influenced: ratio_for(coverage[:deploy_test]) >= 0.45 && ratio_for(coverage[:unit_tests]) >= 0.45 && ratio_for(coverage[:sast]) >= 0.45 && ratio_for(coverage[:scan]) >= 0.45,
        cross_component: @pipeline.downstream_references.any? || all_pipelines.size > 1
      }
    end

    def family_labels(families)
      Array(families).uniq.map { |family| tool_family_label(family) }
    end

    def evaluate_question_build_process_formally_described(context)
      if context[:build_jobs].any? && context[:stages_present] && context[:workflow_governed]
        extra = context[:artifact_signing_tools].any? ? " Build-time integrity material is also generated (#{family_labels(context[:artifact_signing_tools]).join(', ')})." : ""
        question_result("pass", "Build logic is codified in the pipeline with explicit stages and workflow governance.#{extra}")
      elsif context[:build_jobs].any?
        question_result("warn", "Build logic exists in CI/CD YAML, but explicit stages or workflow governance are incomplete.", "Keep the build as code in version control with explicit stages and `workflow:rules` for repeatability.")
      else
        question_result("fail", "No repeatable build flow was detected in the analyzed YAML.", "Define the full build path in version-controlled CI/CD jobs rather than relying on manual or undocumented build steps.")
      end
    end

    def evaluate_question_dependency_knowledge_baseline(context)
      tools = family_labels(context[:dependency_scan_tools])
      if context[:dependency_scan_reports].any? && context[:sbom_present]
        question_result("pass", "Dependency scanning reports and SBOM-style artifacts are published#{tools.any? ? " using #{tools.join(', ')}" : ''}.")
      elsif context[:dependency_scan_tools].any? || context[:sbom_present]
        question_result("warn", "Some dependency visibility exists#{tools.any? ? " through #{tools.join(', ')}" : ''}, but report depth or SBOM evidence is incomplete.", "Publish dependency-scanning reports plus SBOM artifacts such as CycloneDX to improve dependency inventory quality.")
      else
        question_result("fail", "No dependency inventory or dependency-risk signal was detected in the build path.", "Add dependency scanning and publish SBOM artifacts so affected applications can be identified quickly.")
      end
    end

    def evaluate_question_build_process_fully_automated(context)
      if context[:build_jobs].empty?
        question_result("fail", "No build automation path was detected in the analyzed YAML.", "Move the build path into non-manual CI jobs.")
      elsif context[:build_manual_jobs].any?
        question_result("fail", "At least one build-path job is manual, so the build is not fully automated.", "Remove manual gates from the build path or restrict them to post-build release approvals.")
      elsif context[:build_secret_tools].any?
        question_result("pass", "The build path runs without manual interaction and references external secret management (#{family_labels(context[:build_secret_tools]).join(', ')}).")
      else
        question_result("warn", "The build path appears automated, but no external secret-management signal was detected for build tooling.", "Use a managed secret source for build credentials and keep the build path fully non-interactive.")
      end
    end

    def evaluate_question_dependency_risk_formal_process(context)
      tools = family_labels(context[:dependency_scan_tools])
      if context[:dependency_scan_enforced] && context[:license_scan_present] && (context[:dependency_scan_reports].any? || context[:sbom_present])
        question_result("pass", "Dependency risk is gated by enforced scanning#{tools.any? ? " via #{tools.join(', ')}" : ''}, with extra evidence from license or SBOM artifacts.")
      elsif context[:dependency_scan_enforced] || context[:dependency_scan_tools].any?
        question_result("warn", "Dependency-risk checks are present#{tools.any? ? " via #{tools.join(', ')}" : ''}, but the pipeline does not show the fuller process expected for approvals, license, and package hygiene.", "Add enforced dependency scanning together with SBOM or license evidence and treat findings as a release gate.")
      else
        question_result("fail", "No formal dependency-risk process signal was detected on the build path.", "Add dependency scanning and license or SBOM checks, then block releases on unacceptable dependency risk.")
      end
    end

    def evaluate_question_automated_security_checks_in_build(context)
      if context[:sast_ratio] >= 0.85 && context[:scan_ratio] >= 0.85 && context[:gated]
        question_result("pass", "Build security checks are automated and blocking across supported scenarios.")
      elsif context[:sast_ratio] >= 0.45 || context[:scan_ratio] >= 0.45
        question_result("warn", "Some automated build-time security checks exist, but coverage or gate strength is incomplete.", "Enforce stack-appropriate SAST and dependency or image scanning with blocking behavior on all supported paths.")
      else
        question_result("fail", "Automated security checks are missing or not enforced on the build path.", "Add mandatory SAST and dependency or image scanning to the build path and remove `allow_failure` from critical jobs.")
      end
    end

    def evaluate_question_vulnerable_dependencies_block_build(context)
      tools = family_labels(context[:dependency_scan_tools])
      if context[:dependency_scan_enforced]
        question_result("pass", "Dependency scanning#{tools.any? ? " via #{tools.join(', ')}" : ''} is enforced without optional gate behavior on the build path.")
      elsif context[:dependency_scan_tools].any?
        question_result("warn", "Dependency scanning exists#{tools.any? ? " via #{tools.join(', ')}" : ''}, but the build path does not clearly fail on unacceptable dependency risk.", "Make dependency scans blocking and capture accepted-risk exceptions outside the YAML.")
      else
        question_result("fail", "No dependency-vulnerability gate was detected in the build path.", "Add a blocking dependency scan job that fails the build on disallowed vulnerabilities.")
      end
    end

    def evaluate_question_repeatable_deployment_processes(context)
      if context[:deploy_jobs].empty?
        question_result("fail", "No deployment process was detected in the analyzed YAML.", "Define deployment jobs in CI/CD with explicit environments and release stages.")
      elsif context[:environments].any? && context[:manual_deploy_jobs].empty?
        question_result("pass", "Deployment is codified with explicit environments and no manual steps on the supported deployment path.")
      elsif context[:environments].any?
        question_result("warn", "Deployment jobs declare environments, but manual intervention is still part of the deployment path.", "Reduce manual deployment steps or keep them limited to explicit approval stages outside the repeatable deployment flow.")
      else
        question_result("warn", "Deployment jobs exist, but they do not declare explicit environments.", "Declare environments in deployment jobs so the release process is easier to repeat and audit.")
      end
    end

    def evaluate_question_least_privilege_secrets(context)
      if context[:inline_secret_findings].any?
        question_result("fail", "Sensitive variable findings indicate secrets may be handled directly in YAML or pipeline variables.", "Move secrets to a managed secret store and remove inline secret material from pipeline definitions.")
      elsif context[:secret_management_tools].any?
        question_result("pass", "Deployment automation references managed secrets through #{family_labels(context[:secret_management_tools]).join(', ')}.")
      elsif context[:deploy_jobs].any?
        question_result("warn", "Deployment exists, but no managed secret-access signal was detected.", "Use an external secret manager so deployments do not rely on broad variable exposure.")
      else
        question_result("fail", "No deployment-secret handling path was detected.", "Introduce managed secret retrieval in deployment automation.")
      end
    end

    def evaluate_question_deployment_automation_with_security_checks(context)
      if context[:deploy_ratio] >= 0.85 && context[:gating] && context[:manual_deploy_jobs].empty?
        question_result("pass", "Deployment is automated and follows earlier quality and security checks on supported scenarios.")
      elsif context[:deploy_ratio] >= 0.45 && context[:gating]
        question_result("warn", "Deployment automation exists and is partially gated by security checks, but coverage is incomplete or manual steps remain.", "Automate deployment on all supported paths and keep test, SAST, and scan controls as blocking predecessors.")
      else
        question_result("fail", "Deployment is not clearly automated with security checks on the supported path.", "Add automated deployment jobs that depend on test and security gates.")
      end
    end

    def evaluate_question_deployment_secret_injection(context)
      if context[:inline_secret_findings].any?
        question_result("fail", "Inline secret findings reduce confidence that production secrets are injected safely during deployment.", "Fetch secrets at deploy time from a managed store instead of storing active secret values in source or pipeline variables.")
      elsif context[:secret_management_tools].any? && context[:deploy_jobs].any?
        question_result("pass", "Deployment jobs fetch secrets dynamically through #{family_labels(context[:secret_management_tools]).join(', ')}.")
      elsif context[:deploy_jobs].any?
        question_result("warn", "Deployment exists, but no dynamic production-secret injection signal was detected.", "Inject secrets during deployment from a managed secret source rather than embedding them in repository files or static variables.")
      else
        question_result("fail", "No deployment path was detected, so secret injection behavior cannot be demonstrated.", "Define deployment jobs and use managed secret retrieval during release.")
      end
    end

    def evaluate_question_deployed_artifact_integrity_validation(context)
      verify_labels = family_labels(context[:integrity_verification_tools])
      signing_labels = family_labels(context[:artifact_signing_tools])
      if context[:integrity_verification_tools].any? && context[:artifact_signing_tools].any?
        question_result("pass", "Deployment validates artifact integrity using #{verify_labels.join(', ')} against build-time signing or checksum evidence (#{signing_labels.join(', ')}).")
      elsif context[:integrity_verification_tools].any?
        question_result("warn", "Integrity verification exists (#{verify_labels.join(', ')}), but build-time signing or checksum generation was not detected.", "Generate signatures or checksums during the build and verify them before deployment.")
      else
        question_result("fail", "No deployment-time integrity verification was detected.", "Verify signatures or checksums before deployment and fail or roll back on integrity mismatches.")
      end
    end

    def evaluate_question_secret_lifecycle_management(context)
      if context[:secret_management_tools].any?
        question_result("review", "Managed secret tooling is present (#{family_labels(context[:secret_management_tools]).join(', ')}), but rotation cadence and per-instance uniqueness require manual verification.", "Review secret rotation, synchronization, and per-environment uniqueness in the secret-management platform.")
      else
        question_result("fail", "No managed secret-lifecycle signal was detected for deployment automation.", "Adopt a managed secret platform with rotation and instance-specific secret handling.")
      end
    end

    def evaluate_question_known_security_defects_tracking(context)
      if context[:security_reports].any? && context[:structured_reporting]
        question_result("pass", "Machine-readable security reports and structured test or coverage reporting are exported from the pipeline.")
      elsif context[:security_reports].any?
        question_result("warn", "Security report artifacts exist, but supporting structured reporting is incomplete.", "Publish structured report artifacts consistently so findings can be aggregated more easily.")
      else
        question_result("fail", "No machine-readable security defect artifacts were detected.", "Export SAST or scan findings as machine-readable artifacts so defects can be tracked in accessible systems.")
      end
    end

    def evaluate_question_defect_metrics_quick_wins(context)
      if context[:security_reports].any? && context[:structured_reporting]
        question_result("review", "The pipeline exports structured defect data that could feed quick-win metrics, but the review and improvement loop must be confirmed outside CI/CD.", "Verify that exported findings are aggregated and used for recurring improvement actions.")
      elsif context[:security_reports].any? || context[:structured_reporting]
        question_result("warn", "Some metric-ready artifacts exist, but the pipeline evidence is too thin to support a quick-win defect loop.", "Publish both structured test metrics and machine-readable security findings to support defect analytics.")
      else
        question_result("fail", "No structured defect metrics signal was detected.", "Export structured findings so defect trends can be analyzed and acted upon.")
      end
    end

    def evaluate_question_organizational_defect_overview(context)
      if context[:security_reports].any? && context[:cross_component]
        question_result("review", "Cross-component pipeline evidence exists, but organization-wide severity schemes, SLAs, and roll-up dashboards require external defect-management systems.", "Review whether defect data from multiple pipelines is normalized into a central view with shared severities and SLAs.")
      elsif context[:security_reports].any?
        question_result("review", "Project-level defect data exists, but organization-wide aggregation and shared severity schemes still require manual validation outside the current YAML view.", "Aggregate machine-readable findings from multiple pipelines into a shared defect-management view.")
      else
        question_result("fail", "No structured security-defect data was detected for broader aggregation.", "Export machine-readable security findings before attempting organization-level rollups.")
      end
    end

    def evaluate_question_standardized_defect_metrics_program(context)
      if context[:security_reports].any? && context[:structured_reporting]
        question_result("review", "Standardizable defect data exists, but management reporting and program improvements cannot be proven from YAML alone.", "Verify that exported metrics are standardized and regularly reviewed by both engineering and leadership.")
      elsif context[:security_reports].any?
        question_result("warn", "Some security metrics data exists, but it is not enough to demonstrate a standardized improvement program.", "Publish richer structured reports and connect them to program-level dashboards.")
      else
        question_result("fail", "No standardized defect-metrics input was detected in the pipeline.", "Export consistent machine-readable findings and test reports that can feed a shared metrics program.")
      end
    end

    def evaluate_question_defect_sla_enforcement(context)
      if context[:security_reports].any? && context[:blocking_gates]
        question_result("review", "Blocking security signals exist, but SLA tracking, breach alerts, and risk transfers require external defect-management workflow evidence.", "Review ticketing and risk-management integrations to confirm SLA enforcement for security findings.")
      elsif context[:security_reports].any?
        question_result("warn", "Security findings are exported, but the pipeline does not show SLA enforcement behavior.", "Connect exported findings to defect-management tooling with severity and SLA handling.")
      else
        question_result("fail", "No structured security-defect feed was detected to support SLA enforcement.", "Export machine-readable findings before attempting SLA tracking.")
      end
    end

    def evaluate_question_security_metrics_effectiveness(context)
      if context[:security_reports].any? && context[:structured_reporting]
        question_result("review", "The pipeline emits metric-ready data, but metric validation and strategy impact must be verified in reporting and governance systems.", "Review whether exported metrics are checked for accuracy and used to drive security strategy.")
      elsif context[:security_reports].any?
        question_result("warn", "Some metric inputs exist, but they are not enough to demonstrate effective security-metric evaluation.", "Combine machine-readable findings with structured test metrics and external reporting workflows.")
      else
        question_result("fail", "No metric-ready security defect evidence was detected in the pipeline.", "Export structured findings so metric effectiveness can be evaluated outside the pipeline.")
      end
    end

    def unique_active_jobs(active_scenarios)
      index = {}
      active_scenarios.each do |scenario|
        scenario[:jobs].each do |job|
          index[[job[:pipeline_path], job[:name]]] ||= job
        end
      end
      index.values
    end

    def samm_secure_build(jobs, coverage, security_findings)
      unit_ratio = ratio_for(coverage[:unit_tests])
      coverage_ratio = ratio_for(coverage[:coverage_report])
      sast_ratio = ratio_for(coverage[:sast])
      scan_ratio = ratio_for(coverage[:scan])
      workflow_governed = all_pipelines.none? { |pipeline| pipeline.workflow.empty? }
      gated = security_findings.none? { |finding| finding[:title].include?("allow_failure") }
      orchestration_status = if effective_stages.any? && workflow_governed
                               "pass"
                             elsif effective_stages.any? || workflow_governed
                               "warn"
                             else
                               "fail"
                             end
      good_signals = []
      gaps = []
      rules = []

      good_signals << "Build flow uses explicit stages" if effective_stages.any?
      good_signals << "Unit tests are part of active build paths" if unit_ratio >= 0.45
      good_signals << "Coverage evidence is published" if coverage_ratio >= 0.45
      good_signals << "SAST is embedded into the build path" if sast_ratio >= 0.45
      good_signals << "Dependency or image scanning is embedded into the build path" if scan_ratio >= 0.45
      good_signals << "Quality and security gates are blocking" if gated
      good_signals << "workflow:rules governs pipeline creation" if workflow_governed

      gaps << "Unit tests are not consistently enforced across active scenarios" if unit_ratio < 0.45
      gaps << "Coverage artifacts are not consistently published" if coverage_ratio < 0.45
      gaps << "SAST is missing or does not meet the detected stack policy" if sast_ratio < 0.85
      gaps << "Artifact or image scanning is missing on part of the build path" if scan_ratio < 0.45
      gaps << "Some pipelines still rely on job-level rules without workflow governance" unless workflow_governed
      gaps << "At least one quality or security job is optional because allow_failure is enabled" unless gated

      score = 0
      score += 10 if effective_stages.any?
      score += 10 if workflow_governed
      score += (unit_ratio * 20).round
      score += (coverage_ratio * 10).round
      score += (sast_ratio * 25).round
      score += (scan_ratio * 15).round
      score += 10 if gated
      score = [score, 100].min

      rules << benchmark_rule(
        "Repeatable build orchestration is visible",
        orchestration_status,
        if orchestration_status == "pass"
          "Explicit stages are declared and workflow governance is visible on every analyzed pipeline file."
        elsif effective_stages.any?
          "An explicit stage model exists, but at least one analyzed pipeline file still lacks workflow governance."
        else
          "No explicit stage model or consistent workflow governance was detected."
        end
      )
      rules << benchmark_rule(
        "Unit tests execute across supported build paths",
        score_status(unit_ratio),
        "#{status_summary(coverage[:unit_tests])} across active scenarios."
      )
      rules << benchmark_rule(
        "Coverage evidence is published for build outputs",
        score_status(coverage_ratio),
        "#{status_summary(coverage[:coverage_report])} across active scenarios."
      )
      rules << benchmark_rule(
        "Stack-aware SAST is enforced in the build flow",
        score_status(sast_ratio),
        "#{status_summary(coverage[:sast])} across active scenarios."
      )
      rules << benchmark_rule(
        "Artifact or image scanning is enforced on the build path",
        score_status(scan_ratio),
        "#{status_summary(coverage[:scan])} across active scenarios."
      )
      rules << benchmark_rule(
        "Critical quality and security gates block progression",
        gated ? "pass" : "fail",
        gated ? "No `allow_failure` exception was detected on critical quality or security jobs." : "At least one quality or security job is optional because `allow_failure` is enabled."
      )
      questions = assess_implementation_questions("secure_build", secure_build_question_context(jobs, coverage, security_findings))

      benchmark_practice(
        "secure_build",
        "Secure Build",
        score,
        estimate_samm_level(score, level_three: score >= 85 && unit_ratio >= 0.85 && sast_ratio >= 0.85 && scan_ratio >= 0.85 && gated, level_two: score >= 55 && unit_ratio >= 0.45 && sast_ratio >= 0.45),
        "high",
        "Derived from build repeatability, testing, SAST, and dependency or image scanning signals in the pipeline.",
        good_signals,
        gaps,
        rules,
        questions
      )
    end

    def samm_secure_deployment(jobs, coverage, security_findings)
      deploy_ratio = ratio_for(coverage[:deploy_test])
      environment_count = jobs.map { |job| job[:environment] }.compact.uniq.size
      deploy_jobs = jobs.select { |job| deployment_job?(job) }
      production_present = jobs.any? { |job| job[:classifications].include?("deploy_prod") }
      secret_tools = jobs.flat_map { |job| detect_secret_management_tools(job[:script_lines].join("\n").downcase) }.uniq
      integrity_tools = jobs.flat_map { |job| detect_integrity_verification_tools(job[:script_lines].join("\n").downcase) }.uniq
      gating = ratio_for(coverage[:unit_tests]) >= 0.45 && ratio_for(coverage[:sast]) >= 0.45 && ratio_for(coverage[:scan]) >= 0.45
      deploy_hygiene = security_findings.none? do |finding|
        finding[:title].include?("Sensitive variable") || finding[:title].include?("Host key verification") || finding[:title].include?("Remote script download")
      end
      good_signals = []
      gaps = []
      rules = []

      good_signals << "Deployment jobs declare explicit environments" if environment_count.positive?
      good_signals << "Test deployment is automated on the happy path" if deploy_ratio >= 0.45
      good_signals << "Deployment runs after quality and security gates" if gating
      good_signals << "External secret management is referenced in deployment automation" if secret_tools.any?
      good_signals << "Artifact integrity verification is present before deployment" if integrity_tools.any?
      good_signals << "A production deployment path is defined" if production_present
      good_signals << "No deployment hygiene policy violations were detected" if deploy_hygiene

      gaps << "No deployment jobs with explicit environments were detected" if deploy_jobs.empty?
      gaps << "Test deployment is missing or manual in part of the supported paths" if deploy_ratio < 0.45
      gaps << "Deployment is not clearly gated by tests and security scans" unless gating
      gaps << "No external secret manager signal was detected in deployment automation" if secret_tools.empty?
      gaps << "No signature or checksum verification was detected before deployment" if integrity_tools.empty?
      gaps << "No production deployment path was detected" unless production_present
      gaps << "Deployment hygiene findings reduce confidence in secure deployment" unless deploy_hygiene

      score = 0
      score += 15 if environment_count.positive?
      score += (deploy_ratio * 30).round
      score += 15 if gating
      score += 15 if secret_tools.any?
      score += 15 if integrity_tools.any?
      score += 5 if production_present
      score += 5 if deploy_hygiene
      score = [score, 100].min

      rules << benchmark_rule(
        "Deployment jobs declare explicit environments",
        environment_count.positive? ? "pass" : "fail",
        environment_count.positive? ? "Detected #{environment_count} explicit environment declaration(s)." : "No deployment job with an explicit environment declaration was detected."
      )
      rules << benchmark_rule(
        "A test environment deployment is automated",
        score_status(deploy_ratio),
        "#{status_summary(coverage[:deploy_test])} across active scenarios."
      )
      rules << benchmark_rule(
        "Deployment is gated by tests and security scans",
        gating ? "pass" : "fail",
        gating ? "Unit tests, SAST, and artifact or image scanning all appear on the supported path before deployment." : "Deployment is not clearly gated by the expected test and security controls."
      )
      rules << benchmark_rule(
        "External secret management is referenced in deployment automation",
        secret_tools.any? ? "pass" : "fail",
        secret_tools.any? ? "Detected #{secret_tools.map { |family| tool_family_label(family) }.join(', ')} in deployment automation." : "No external secret-management signal was detected in deployment automation."
      )
      rules << benchmark_rule(
        "Artifact integrity is verified before deployment",
        integrity_tools.any? ? "pass" : "fail",
        integrity_tools.any? ? "Detected #{integrity_tools.map { |family| tool_family_label(family) }.join(', ')} before deployment." : "No signature or checksum verification was detected before deployment."
      )
      rules << benchmark_rule(
        "A production deployment path is visible",
        production_present ? "pass" : "warn",
        production_present ? "A production deployment path is defined in the analyzed YAML." : "No production deployment path was detected in the analyzed YAML."
      )
      rules << benchmark_rule(
        "Deployment hygiene remains policy-compliant",
        deploy_hygiene ? "pass" : "fail",
        deploy_hygiene ? "No high-risk deployment hygiene violations were detected." : "Deployment hygiene findings lower confidence in secure deployment."
      )
      questions = assess_implementation_questions("secure_deployment", secure_deployment_question_context(jobs, coverage, security_findings))

      benchmark_practice(
        "secure_deployment",
        "Secure Deployment",
        score,
        estimate_samm_level(score, level_three: score >= 85 && deploy_ratio >= 0.85 && secret_tools.any? && integrity_tools.any?, level_two: score >= 55 && deploy_ratio >= 0.45 && gating),
        "medium",
        "Derived from deployment automation, secret-management signals, integrity verification, and gate enforcement in the pipeline.",
        good_signals,
        gaps,
        rules,
        questions
      )
    end

    def samm_defect_management(jobs, coverage, security_findings)
      unit_ratio = ratio_for(coverage[:unit_tests])
      sast_ratio = ratio_for(coverage[:sast])
      scan_ratio = ratio_for(coverage[:scan])
      deploy_ratio = ratio_for(coverage[:deploy_test])
      report_families = jobs.flat_map { |job| Array(job[:report_families]) }.uniq
      security_reports = report_families & %w[sast_report dependency_scanning_report container_scanning_report]
      structured_reporting = report_families.include?("junit") || report_families.include?("coverage_report")
      blocking_gates = security_findings.none? { |finding| finding[:title].include?("allow_failure") }
      flow_influenced = deploy_ratio >= 0.45 && unit_ratio >= 0.45 && sast_ratio >= 0.45 && scan_ratio >= 0.45
      cross_component = @pipeline.downstream_references.any? || all_pipelines.size > 1
      good_signals = []
      gaps = []
      rules = []

      good_signals << "Structured test reports are published" if structured_reporting
      good_signals << "Security defect reports are exported as machine-readable artifacts" if security_reports.any?
      good_signals << "Tests and scans act as blocking defect gates" if blocking_gates && unit_ratio >= 0.45 && (sast_ratio >= 0.45 || scan_ratio >= 0.45)
      good_signals << "Deployment is influenced by quality and security findings" if flow_influenced
      good_signals << "Multiple pipeline components are analyzed together" if cross_component

      gaps << "No structured test reporting was detected" unless structured_reporting
      gaps << "No machine-readable SAST or scan report artifacts were detected" if security_reports.empty?
      gaps << "Quality or security findings do not consistently block the flow" unless blocking_gates && unit_ratio >= 0.45 && (sast_ratio >= 0.45 || scan_ratio >= 0.45)
      gaps << "Deployment is not clearly influenced by earlier defect signals" unless flow_influenced
      gaps << "The current YAML view does not show cross-component defect feedback loops" unless cross_component

      score = 0
      score += (unit_ratio * 20).round
      score += (sast_ratio * 20).round
      score += (scan_ratio * 15).round
      score += 15 if structured_reporting
      score += 10 if security_reports.any?
      score += 10 if blocking_gates
      score += 5 if flow_influenced
      score += 5 if cross_component
      score = [score, 100].min

      rules << benchmark_rule(
        "Structured test reporting is published",
        structured_reporting ? "pass" : "fail",
        structured_reporting ? "Detected structured test or coverage report artifacts in the analyzed jobs." : "No structured test or coverage report artifacts were detected."
      )
      rules << benchmark_rule(
        "Machine-readable security defect reports are exported",
        security_reports.any? ? "pass" : "fail",
        security_reports.any? ? "Detected #{security_reports.map { |family| tool_family_label(family) }.join(', ')} artifacts." : "No machine-readable SAST or scan report artifact was detected."
      )
      rules << benchmark_rule(
        "Tests and scans act as blocking defect gates",
        blocking_gates && unit_ratio >= 0.45 && (sast_ratio >= 0.45 || scan_ratio >= 0.45) ? "pass" : "fail",
        if blocking_gates
          "Unit test, SAST, and scan coverage is able to influence the flow without `allow_failure` on critical jobs."
        else
          "At least one critical test or scan job is optional because `allow_failure` is enabled."
        end
      )
      rules << benchmark_rule(
        "Deployment is influenced by earlier defect signals",
        flow_influenced ? "pass" : "warn",
        flow_influenced ? "Deployment follows earlier quality and security controls on the analyzed path." : "The analyzed flow does not clearly show deployment reacting to earlier defect signals."
      )
      rules << benchmark_rule(
        "Cross-component defect visibility is represented",
        cross_component ? "pass" : "warn",
        cross_component ? "Multiple pipeline components are analyzed together, so cross-component feedback is visible." : "The current YAML view is limited to a single pipeline component."
      )
      questions = assess_implementation_questions("defect_management", defect_management_question_context(jobs, coverage, security_findings))

      benchmark_practice(
        "defect_management",
        "Defect Management",
        score,
        estimate_samm_level(score, level_three: score >= 85 && structured_reporting && security_reports.any? && flow_influenced && cross_component, level_two: score >= 55 && structured_reporting && blocking_gates),
        "medium",
        "Derived from machine-readable reports, blocking gates, and whether defects influence later deployment decisions in the pipeline.",
        good_signals,
        gaps,
        rules,
        questions
      )
    end

    def benchmark_practice(key, title, score, estimated_level, confidence, rationale, good_signals, gaps, rules, questions)
      {
        key: key,
        title: title,
        alignment_score: score,
        estimated_level: estimated_level,
        max_level: 3,
        status: score_status(score.to_f / 100.0),
        confidence: confidence,
        rationale: rationale,
        good_signals: good_signals,
        gaps: gaps,
        rules: rules,
        questions: questions,
        question_summary: benchmark_question_summary(questions),
        reference_url: OWASP_SAMM_REFERENCES.fetch(key)
      }
    end

    def benchmark_rule(title, status, detail)
      {
        title: title,
        status: status,
        detail: detail
      }
    end

    def estimate_samm_level(score, level_three:, level_two:)
      return 3 if level_three
      return 2 if level_two
      return 1 if score >= 25

      0
    end

    def deployment_job?(job)
      job[:classifications].include?("deploy_test") || job[:classifications].include?("deploy_prod") || job[:stage].to_s.downcase.include?("deploy")
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
      recommendation = resolve_guidance_value(guidance[:recommendation], status_counts, active_scenarios.size)
      how_to_fix = resolve_guidance_value(guidance[:how_to_fix], status_counts, active_scenarios.size)

      if control_key == :sast
        missing_stack_keys = failing_scenarios.flat_map do |scenario|
          scenario.fetch(:sast_stack_coverage, {}).fetch(:missing_stacks, [])
        end.uniq
        if missing_stack_keys.any?
          recommendation = sast_recommendation_for_stacks(missing_stack_keys)
          how_to_fix = sast_how_to_fix(missing_stack_keys)
        end
      end

      [{
        severity: status == "fail" ? "high" : "medium",
        title: guidance[:title],
        issue: guidance[:issue].call(status_counts, active_scenarios.size),
        recommendation: recommendation,
        how_to_fix: how_to_fix,
        evidence: failing_evidence
      }]
    end

    def resolve_guidance_value(value, status_counts, total)
      return value unless value.respond_to?(:call)

      case value.arity
      when 0
        value.call
      when 1
        value.call(status_counts)
      else
        value.call(status_counts, total)
      end
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
          recommendation: lambda { sast_recommendation_for_stacks(@detected_stacks) },
          how_to_fix: lambda { sast_how_to_fix(@detected_stacks) }
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
      script_evidence = expand_local_script_evidence(pipeline, script_lines)
      artifact_strings = collect_artifact_strings(job["artifacts"])
      environment_name = extract_environment_name(job)
      classifications = classify_job(job_name, job, script_lines, artifact_strings, environment_name, script_evidence)
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
        pipeline_short_label: compact_pipeline_label(relative_pipeline_path(pipeline.path)),
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
        notes: graph_job_notes(pipeline, job, artifact_strings, script_lines)
      }
    end

    def graph_node_id(pipeline, job_name)
      "#{relative_pipeline_path(pipeline.path)}::#{job_name}"
    end

    def compact_pipeline_label(path)
      return path if path.to_s.length <= 36

      segments = path.to_s.split("/")
      return path if segments.length <= 1

      last_two = segments.last(2).join("/")
      return ".../#{last_two}" if last_two.length <= 52

      last_segment = segments.last.to_s
      return ".../#{last_segment}" unless last_segment.empty?

      path
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

    def graph_job_notes(pipeline, job, artifact_strings, script_lines)
      script_evidence = expand_local_script_evidence(pipeline, script_lines)
      script_text = (script_lines + script_evidence[:lines]).join("\n").downcase
      notes = []
      notes << "Artifacts: #{artifact_strings.first(4).join(', ')}" if artifact_strings.any?
      report_families = detect_report_families(artifact_strings)
      notes << "Reports: #{report_families.map { |family| tool_family_label(family) }.join(', ')}" if report_families.any?
      notes << "Local script evidence: #{script_evidence[:files].join(', ')}" if script_evidence[:files].any?
      secret_tools = detect_secret_management_tools(script_text)
      notes << "Secret management: #{secret_tools.map { |family| tool_family_label(family) }.join(', ')}" if secret_tools.any?
      integrity_tools = detect_integrity_verification_tools(script_text)
      notes << "Integrity checks: #{integrity_tools.map { |family| tool_family_label(family) }.join(', ')}" if integrity_tools.any?
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

    def detect_stacks
      text = all_pipelines.flat_map do |pipeline|
        items = []
        items << pipeline.path
        items << extract_image_name(pipeline.raw_config["image"])
        items.concat(pipeline.global_before_script)
        items.concat(pipeline.global_after_script)

        pipeline.jobs.each do |job_name, job|
          script_lines = collect_script_lines(pipeline, job)
          script_evidence = expand_local_script_evidence(pipeline, script_lines)
          items << job_name
          items << job["stage"]
          items << extract_image_name(job["image"])
          items.concat(script_lines)
          items.concat(script_evidence[:lines])
          items.concat(collect_artifact_strings(job["artifacts"]))
        end
        items
      end.compact.join("\n").downcase

      STACK_LABELS.keys.select do |stack_key|
        stack_signal_pattern(stack_key).match?(text)
      end
    end

    def detected_stack_labels
      @detected_stacks.map { |stack_key| STACK_LABELS.fetch(stack_key) }
    end

    def stack_labels_for(stack_keys)
      Array(stack_keys).uniq.map { |stack_key| STACK_LABELS.fetch(stack_key, stack_key) }
    end

    def stack_signal_pattern(stack_key)
      case stack_key
      when "dotnet"
        /\b(dotnet|msbuild|nuget|csharp|fsharp)\b|\.csproj\b|\.sln\b/
      when "node_js"
        /\b(node|npm|npx|pnpm|yarn|next|vite|webpack|angular|react)\b|package(?:-lock)?\.json|pnpm-lock\.yaml|yarn\.lock/
      when "java"
        /\b(mvn|mvnw|gradle|gradlew|java|jar|jdk)\b|pom\.xml|build\.gradle(?:\.kts)?/
      when "python"
        /\b(pytest|pip|poetry|tox|django|flask|python)\b|pyproject\.toml|requirements\.txt|poetry\.lock/
      when "go"
        /\b(go test|golang|go build|gosec)\b|go\.mod/
      when "ruby"
        /\b(bundle exec|rspec|rake|rubocop|ruby|brakeman)\b|gemfile|\.gemspec/
      when "php"
        /\b(phpunit|composer|phpstan|psalm|php|laravel|symfony)\b|composer\.json/
      else
        /$^/
      end
    end

    def sast_recommendation_for_stacks(stack_keys)
      recommendation = "Add a mandatory SAST stage for every supported branch and merge request path."
      labels = stack_labels_for(stack_keys)
      recommendation += " Align the tooling with the detected stack: #{labels.join(', ')}." if labels.any?
      recommendation
    end

    def sast_how_to_fix(stack_keys = @detected_stacks)
      generic = "The simplest baseline is `include: - template: Jobs/SAST.gitlab-ci.yml`, or add an enforcing scanner job and remove `allow_failure`."
      stack_guidance = Array(stack_keys).uniq.map { |stack_key| sast_guidance_for_stack(stack_key) }.compact
      return generic if stack_guidance.empty?

      [generic, stack_guidance.join(" ")].join(" ")
    end

    def sast_guidance_for_stack(stack_key)
      case stack_key
      when "dotnet"
        "For .NET, prefer `dotnet sonarscanner begin/end`, `Security Code Scan`, `semgrep`, or `snyk code test`."
      when "node_js"
        "For Node / JS, prefer `semgrep`, `njsscan`, `nodejsscan`, `sonar-scanner`, or `snyk code test`."
      when "java"
        "For Java, prefer `spotbugs` with `findsecbugs`, `sonar-scanner`, `semgrep`, or `codeql`."
      when "python"
        "For Python, prefer `bandit`, `semgrep`, or `codeql`."
      when "go"
        "For Go, prefer `gosec`, `semgrep`, or `codeql`."
      when "ruby"
        "For Ruby, prefer `brakeman`, `semgrep`, or `codeql`."
      when "php"
        "For PHP, prefer `psalm --taint-analysis`, `progpilot`, `semgrep`, or `codeql`."
      end
    end

    def tool_family_label(family)
      TOOL_LABELS.fetch(family, family.to_s.tr("_", " "))
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
