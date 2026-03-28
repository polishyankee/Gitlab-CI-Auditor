require_relative "test_helper"

class ExpressionEvaluatorTest < Minitest::Test
  def test_evaluates_boolean_and_regex_logic
    variables = {
      "CI_PIPELINE_SOURCE" => "merge_request_event",
      "CI_COMMIT_BRANCH" => "feature/refactor-auth"
    }

    expression = '$CI_PIPELINE_SOURCE == "merge_request_event" && $CI_COMMIT_BRANCH =~ /feature\\//'

    assert_equal true, GitlabCiAuditor::ExpressionEvaluator.evaluate(expression, variables)
  end

  def test_evaluates_negation_and_missing_variable_truthiness
    variables = {
      "CI_COMMIT_TAG" => nil,
      "CI_COMMIT_BRANCH" => "main"
    }

    expression = '!$CI_COMMIT_TAG && $CI_COMMIT_BRANCH == "main"'

    assert_equal true, GitlabCiAuditor::ExpressionEvaluator.evaluate(expression, variables)
  end

  def test_returns_nil_for_invalid_expression
    assert_nil GitlabCiAuditor::ExpressionEvaluator.evaluate('$CI_COMMIT_BRANCH == ', "CI_COMMIT_BRANCH" => "main")
  end

  def test_consumes_right_side_of_or_expression_even_when_left_side_is_truthy
    variables = {
      "CI_COMMIT_BRANCH" => "main",
      "CI_PIPELINE_SOURCE" => "push"
    }

    expression = '$CI_COMMIT_BRANCH || $CI_PIPELINE_SOURCE == "merge_request_event"'

    assert_equal true, GitlabCiAuditor::ExpressionEvaluator.evaluate(expression, variables)
  end
end
