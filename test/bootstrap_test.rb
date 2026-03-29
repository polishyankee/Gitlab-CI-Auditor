require_relative "test_helper"
require "open3"
require "rbconfig"

class BootstrapTest < Minitest::Test
  def test_core_library_boots_without_webrick_loaded
    lib_dir = File.join(GitlabCiAuditor.root_dir, "lib")
    command = [
      RbConfig.ruby,
      "--disable-gems",
      "-I", lib_dir,
      "-e", 'require "gitlab_ci_auditor"; abort("server loaded eagerly") if defined?(GitlabCiAuditor::Server); puts "ok"'
    ]

    stdout, stderr, status = Open3.capture3(*command)

    assert status.success?, stderr
    assert_equal "ok\n", stdout
  end
end
