require_relative "test_helper"

class ServerTest < Minitest::Test
  RequestStub = Struct.new(:query)

  def test_analyze_request_allows_nil_snapshot_file_in_gui_flow
    GitlabCiAuditor.require_server!

    server = GitlabCiAuditor::Server.new(
      host: "127.0.0.1",
      port: 4567
    )

    report = server.send(
      :analyze_request,
      RequestStub.new(
        {
          "pipeline_path" => fixture("good_pipeline.yml"),
          "policy_pack" => "balanced"
        }
      )
    )

    assert_equal "complete", report[:summary][:analysis_scope]
    assert report[:summary][:overall_score] >= 75
  rescue LoadError => error
    skip(error.message)
  end
end
