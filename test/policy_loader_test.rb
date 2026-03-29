require_relative "test_helper"

class PolicyLoaderTest < Minitest::Test
  def test_loads_bundled_pack_with_meta
    policy = GitlabCiAuditor::PolicyLoader.load(pack: "strict")

    assert_equal "strict", policy.dig("meta", "name")
    assert_equal "Strict Platform", policy.dig("meta", "label")
    assert_equal true, policy.dig("required_controls", "coverage_report")
    assert_equal true, policy.dig("security_policies", "forbid_unpinned_images")
    assert_includes policy.dig("stack_sast_requirements", "dotnet", "accepted_families"), "dotnet_sonarscanner"
    assert_includes policy.dig("stack_sast_requirements", "node_js", "accepted_families"), "njsscan"
  end

  def test_loads_custom_policy_file_and_adds_meta_defaults
    Dir.mktmpdir do |dir|
      custom_path = File.join(dir, "custom.json")
      File.write(custom_path, JSON.pretty_generate({ "required_controls" => { "unit_tests" => true } }))

      policy = GitlabCiAuditor::PolicyLoader.load(path: custom_path)

      assert_equal "custom", policy.dig("meta", "name")
      assert_equal "Custom Policy File", policy.dig("meta", "label")
      assert_equal "file", policy.dig("meta", "source")
    end
  end
end
