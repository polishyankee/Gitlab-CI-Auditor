Dir[File.join(__dir__, "*_test.rb")].sort.each do |path|
  require path
end

require File.join(__dir__, "test_gitlab_ci_auditor.rb")
