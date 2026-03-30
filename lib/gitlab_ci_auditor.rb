require "json"
require "erb"
require "yaml"
require "ostruct"
require "time"
require "strscan"
require "optparse"
require "tmpdir"
require "csv"
require "shellwords"

module GitlabCiAuditor
  VERSION = "0.3.0".freeze

  RESERVED_KEYS = %w[
    after_script
    before_script
    cache
    default
    image
    include
    interruptible
    pages
    services
    spec
    stages
    timeout
    types
    variables
    workflow
  ].freeze

  SENSITIVE_KEY_PATTERN = /(token|password|passwd|api[_-]?key|private[_-]?key|access[_-]?key|secret[_-]?key|auth[_-]?pass|bootstrap[_-]?password)/i

  def self.root_dir
    File.expand_path("..", __dir__)
  end

  def self.deep_copy(value)
    case value
    when Hash
      value.each_with_object({}) { |(key, item), copy| copy[key] = deep_copy(item) }
    when Array
      value.map { |item| deep_copy(item) }
    else
      value
    end
  end

  def self.deep_merge(base, override)
    return deep_copy(override) if base.nil?
    return deep_copy(base) if override.nil?
    return deep_copy(override) unless base.is_a?(Hash) && override.is_a?(Hash)

    merged = deep_copy(base)
    override.each do |key, value|
      merged[key] =
        if merged[key].is_a?(Hash) && value.is_a?(Hash)
          deep_merge(merged[key], value)
        else
          deep_copy(value)
        end
    end
    merged
  end

  def self.normalize_array(value)
    case value
    when nil
      []
    when Array
      value.flatten.compact.map(&:to_s)
    else
      [value.to_s]
    end
  end

  def self.job_definition?(name, value)
    value.is_a?(Hash) && !RESERVED_KEYS.include?(name)
  end

  def self.require_server!
    require_relative "gitlab_ci_auditor/server"
  end
end

require_relative "gitlab_ci_auditor/policy_loader"
require_relative "gitlab_ci_auditor/pipeline_loader"
require_relative "gitlab_ci_auditor/rule_evaluator"
require_relative "gitlab_ci_auditor/analyzer"
require_relative "gitlab_ci_auditor/report_renderer"
require_relative "gitlab_ci_auditor/cli"
