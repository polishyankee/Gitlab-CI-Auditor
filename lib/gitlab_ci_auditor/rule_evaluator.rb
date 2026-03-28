module GitlabCiAuditor
  class ExpressionEvaluator
    def self.evaluate(expression, variables)
      new(expression, variables).evaluate
    end

    def initialize(expression, variables)
      @expression = expression.to_s.strip
      @variables = variables
      @tokens = []
      @index = 0
    end

    def evaluate
      return true if @expression.empty?

      tokenize
      result = parse_or
      expect(:eof)
      truthy?(result)
    rescue StandardError
      nil
    end

    private

    Token = Struct.new(:type, :value, keyword_init: true)

    def tokenize
      scanner = StringScanner.new(@expression)
      until scanner.eos?
        if scanner.scan(/\s+/)
          next
        elsif scanner.scan(/\(/)
          @tokens << Token.new(type: :lparen, value: "(")
        elsif scanner.scan(/\)/)
          @tokens << Token.new(type: :rparen, value: ")")
        elsif scanner.scan(/\&\&/)
          @tokens << Token.new(type: :and, value: "&&")
        elsif scanner.scan(/\|\|/)
          @tokens << Token.new(type: :or, value: "||")
        elsif scanner.scan(/!~/)
          @tokens << Token.new(type: :not_match, value: "!~")
        elsif scanner.scan(/=~/)
          @tokens << Token.new(type: :match, value: "=~")
        elsif scanner.scan(/!=/)
          @tokens << Token.new(type: :neq, value: "!=")
        elsif scanner.scan(/==/)
          @tokens << Token.new(type: :eq, value: "==")
        elsif scanner.scan(/!/)
          @tokens << Token.new(type: :not, value: "!")
        elsif (regex = scanner.scan(%r{/(?:\\.|[^/])*/[imx]*}))
          @tokens << Token.new(type: :regex, value: regex)
        elsif (string = scanner.scan(/"(?:\\.|[^"])*"/)) || (string = scanner.scan(/'(?:\\.|[^'])*'/))
          @tokens << Token.new(type: :string, value: unquote(string))
        elsif (variable = scanner.scan(/\$[A-Za-z_][A-Za-z0-9_]*/))
          @tokens << Token.new(type: :variable, value: variable[1..])
        elsif scanner.scan(/\bnull\b/)
          @tokens << Token.new(type: :null, value: nil)
        elsif scanner.scan(/\btrue\b/)
          @tokens << Token.new(type: :boolean, value: true)
        elsif scanner.scan(/\bfalse\b/)
          @tokens << Token.new(type: :boolean, value: false)
        elsif (identifier = scanner.scan(/[A-Za-z0-9_.:@\/-]+/))
          @tokens << Token.new(type: :identifier, value: identifier)
        else
          raise ArgumentError, "Unsupported token near #{scanner.rest.inspect}"
        end
      end

      @tokens << Token.new(type: :eof, value: nil)
    end

    def unquote(string)
      body = string[1..-2]
      body.gsub(/\\(["'])/, '\1')
    end

    def parse_or
      left = parse_and
      while accept(:or)
        right = parse_and
        left = truthy?(left) || truthy?(right)
      end
      left
    end

    def parse_and
      left = parse_comparison
      while accept(:and)
        right = parse_comparison
        left = truthy?(left) && truthy?(right)
      end
      left
    end

    def parse_comparison
      left = parse_unary
      token = current
      return left unless %i[eq neq match not_match].include?(token.type)

      advance
      right = parse_unary
      case token.type
      when :eq
        comparable(left) == comparable(right)
      when :neq
        comparable(left) != comparable(right)
      when :match
        regex_match?(left, right)
      when :not_match
        !regex_match?(left, right)
      else
        false
      end
    end

    def parse_unary
      return !truthy?(parse_unary) if accept(:not)

      parse_primary
    end

    def parse_primary
      token = current
      case token.type
      when :variable
        advance
        @variables[token.value]
      when :string, :identifier, :boolean
        advance
        token.value
      when :null
        advance
        nil
      when :regex
        advance
        build_regex(token.value)
      when :lparen
        advance
        value = parse_or
        expect(:rparen)
        value
      else
        raise ArgumentError, "Unexpected token #{token.type}"
      end
    end

    def build_regex(raw)
      body = raw[1..]
      delimiter = body.rindex("/")
      pattern = body[0...delimiter]
      flags = body[(delimiter + 1)..]
      options = 0
      options |= Regexp::IGNORECASE if flags&.include?("i")
      Regexp.new(pattern, options)
    end

    def comparable(value)
      case value
      when nil
        nil
      when true, false
        value
      when Regexp
        value.source
      else
        value.to_s
      end
    end

    def regex_match?(left, right)
      regex =
        case right
        when Regexp
          right
        else
          Regexp.new(right.to_s)
        end

      !!(left.to_s =~ regex)
    rescue RegexpError
      false
    end

    def truthy?(value)
      case value
      when nil, false
        false
      when String
        !value.strip.empty?
      else
        true
      end
    end

    def current
      @tokens[@index]
    end

    def advance
      @index += 1
    end

    def accept(type)
      return false unless current.type == type

      advance
      true
    end

    def expect(type)
      raise ArgumentError, "Expected #{type}, got #{current.type}" unless current.type == type

      advance
    end
  end

  class RuleEvaluator
    def initialize(pipeline)
      @pipeline = pipeline
    end

    def pipeline_active?(scenario)
      rules = Array(@pipeline.workflow["rules"])
      return true if rules.empty?

      result = evaluate_rules(rules, scenario)
      result[:included]
    end

    def evaluate_job(job_name, job, scenario)
      when_value = job["when"] || "on_success"
      allow_failure = job["allow_failure"] == true

      if job["rules"].is_a?(Array)
        result = evaluate_rules(job["rules"], scenario)
        return result.merge(name: job_name, when: when_value, allow_failure: allow_failure) unless result[:matched]

        when_value = result[:when] || when_value
        allow_failure = result.key?(:allow_failure) ? result[:allow_failure] : allow_failure
        return result.merge(
          name: job_name,
          included: result[:included],
          when: when_value,
          allow_failure: allow_failure,
          manual: when_value == "manual"
        )
      end

      if job.key?("only") || job.key?("except")
        included = only_except_match?(job, scenario)
        return {
          name: job_name,
          matched: true,
          included: included && when_value != "never",
          when: when_value,
          allow_failure: allow_failure,
          manual: when_value == "manual"
        }
      end

      {
        name: job_name,
        matched: true,
        included: when_value != "never",
        when: when_value,
        allow_failure: allow_failure,
        manual: when_value == "manual"
      }
    end

    private

    def evaluate_rules(rules, scenario)
      rules.each do |rule|
        next unless rule_match?(rule, scenario)

        when_value = rule["when"] || "on_success"
        return {
          matched: true,
          included: when_value != "never",
          when: when_value,
          allow_failure: rule["allow_failure"] == true,
          manual: when_value == "manual"
        }
      end

      { matched: false, included: false, when: nil, allow_failure: false, manual: false }
    end

    def rule_match?(rule, scenario)
      matches = []

      if rule.key?("if")
        result = ExpressionEvaluator.evaluate(rule["if"], scenario[:variables])
        matches << (result == true)
      end

      if rule.key?("changes")
        matches << changes_match?(rule["changes"], scenario)
      end

      if rule.key?("exists")
        matches << exists_match?(rule["exists"])
      end

      matches.empty? || matches.all?
    end

    def exists_match?(entries)
      GitlabCiAuditor.normalize_array(entries).any? do |pattern|
        Dir.glob(File.join(@pipeline.base_dir, pattern), File::FNM_EXTGLOB).any?
      end
    end

    def changes_match?(changes_value, scenario)
      changed_files = Array(scenario[:changed_files]).map(&:to_s)
      return false if changed_files.empty?

      patterns = extract_change_patterns(changes_value)
      return changed_files.any? if patterns.empty?

      changed_files.any? do |changed_file|
        patterns.any? { |pattern| change_pattern_match?(pattern, changed_file) }
      end
    end

    def extract_change_patterns(changes_value)
      case changes_value
      when Hash
        GitlabCiAuditor.normalize_array(changes_value["paths"] || changes_value[:paths] || changes_value["changes"])
      else
        GitlabCiAuditor.normalize_array(changes_value)
      end
    end

    def change_pattern_match?(pattern, changed_file)
      normalized_pattern = pattern.to_s.sub(%r{\A\./}, "")
      normalized_file = changed_file.to_s.sub(%r{\A\./}, "")
      File.fnmatch?(normalized_pattern, normalized_file, File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH)
    end

    def only_except_match?(job, scenario)
      only_patterns = normalize_ref_patterns(job["only"])
      except_patterns = normalize_ref_patterns(job["except"])
      only_match = only_patterns.empty? || only_patterns.any? { |pattern| reference_match?(pattern, scenario) }
      except_match = except_patterns.any? { |pattern| reference_match?(pattern, scenario) }
      only_match && !except_match
    end

    def normalize_ref_patterns(value)
      case value
      when nil
        []
      when Hash
        Array(value["refs"] || value[:refs]).map(&:to_s)
      when Array
        value.map(&:to_s)
      else
        [value.to_s]
      end
    end

    def reference_match?(pattern, scenario)
      sanitized = pattern.split("@").first
      ref_name = scenario[:tag] || scenario[:branch]

      case sanitized
      when "branches"
        scenario[:source] == "push" && scenario[:branch] && scenario[:tag].nil?
      when "tags"
        !scenario[:tag].nil?
      when "merge_requests"
        scenario[:source] == "merge_request_event"
      when "schedules"
        scenario[:source] == "schedule"
      when "web"
        scenario[:source] == "web"
      when "api"
        scenario[:source] == "api"
      when "triggers"
        scenario[:source] == "trigger"
      else
        if sanitized.start_with?("/") && sanitized.end_with?("/")
          !!(ref_name.to_s =~ Regexp.new(sanitized[1..-2]))
        else
          ref_name.to_s == sanitized
        end
      end
    rescue RegexpError
      false
    end
  end
end
