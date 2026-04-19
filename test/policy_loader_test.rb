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

  def test_loads_inline_policy_json_with_gui_meta_defaults
    policy = GitlabCiAuditor::PolicyLoader.load_json(
      JSON.generate({ "required_controls" => { "unit_tests" => true } }),
      source: "GUI settings",
      name: "team_policy",
      label: "Team Policy",
      policy_source: "gui_policy"
    )

    assert_equal "team_policy", policy.dig("meta", "name")
    assert_equal "Team Policy", policy.dig("meta", "label")
    assert_equal "gui_policy", policy.dig("meta", "source")
  end

  def test_catalog_entries_expose_bundled_policy_json_for_gui
    entries = GitlabCiAuditor::PolicyLoader.catalog_entries
    balanced = entries.find { |entry| entry[:id] == "pack:balanced" }

    refute_nil balanced
    assert_equal "pack", balanced[:kind]
    assert_includes balanced[:json], "\"required_controls\""
    assert_includes balanced[:json], "\"meta\""
  end

  def test_rejects_unsupported_top_level_policy_keys
    Dir.mktmpdir do |dir|
      custom_path = File.join(dir, "custom.json")
      File.write(custom_path, JSON.pretty_generate({ "unknown_section" => true }))

      error = assert_raises(ArgumentError) do
        GitlabCiAuditor::PolicyLoader.load(path: custom_path)
      end

      assert_includes error.message, "unsupported policy key"
      assert_includes error.message, "unknown_section"
    end
  end

  def test_rejects_invalid_boolean_policy_values
    Dir.mktmpdir do |dir|
      custom_path = File.join(dir, "custom.json")
      File.write(custom_path, JSON.pretty_generate({ "required_controls" => { "unit_tests" => "yes" } }))

      error = assert_raises(ArgumentError) do
        GitlabCiAuditor::PolicyLoader.load(path: custom_path)
      end

      assert_includes error.message, "required_controls.unit_tests"
      assert_includes error.message, "must be a boolean"
    end
  end

  def test_rejects_invalid_severity_tuning_values
    Dir.mktmpdir do |dir|
      custom_path = File.join(dir, "custom.json")
      File.write(custom_path, JSON.pretty_generate({
        "severity_tuning" => {
          "security" => {
            "contains" => {
              "allow_failure" => "urgent"
            }
          }
        }
      }))

      error = assert_raises(ArgumentError) do
        GitlabCiAuditor::PolicyLoader.load(path: custom_path)
      end

      assert_includes error.message, "unsupported severity"
      assert_includes error.message, "urgent"
    end
  end
end
