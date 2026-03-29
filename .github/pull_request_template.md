## Summary

- describe the change clearly
- explain why this change is needed

## Verification

- [ ] `ruby -I lib:test test/run_all.rb`
- [ ] `./bin/gitlab-ci-auditor scan test/fixtures/good_pipeline.yml`
- [ ] Docker verification if the change touches `Dockerfile`, runtime dependencies, or CI container steps

## Impact

- [ ] scoring logic changed
- [ ] policy pack behavior changed
- [ ] report rendering changed
- [ ] GUI behavior changed
- [ ] CI or release flow changed
- [ ] documentation only

## Notes For Reviewers

- mention any fixtures added or updated
- mention any backward compatibility risk
- mention any follow-up work that is intentionally left out
