require "minitest/autorun"
$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "gitlab_ci_auditor"

module GitlabCiAuditorTestHelpers
  def fixture(name)
    File.expand_path(File.join("fixtures", name), __dir__)
  end

  def example_path(relative_path)
    File.expand_path(File.join("..", "examples", relative_path), __dir__)
  end
end

class Minitest::Test
  include GitlabCiAuditorTestHelpers
end
