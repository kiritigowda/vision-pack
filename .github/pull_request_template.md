## Summary

<!-- What does this PR change, and why? -->

## Checklist

- [ ] Builds locally (`cmake --build build`) against a ROCm SDK at `ROCM_PATH`.
- [ ] Does **not** modify any file under a vision-library submodule
      (`mivisionx/`, `rocal/`, `rocCV/`, `rocpydecode/`) — integration is done from
      vision-pack (see [CONTRIBUTING.md](../CONTRIBUTING.md)).
- [ ] CI is green (build, package, smoke-test, findpackage-test).
- [ ] Updated docs (README / CONTRIBUTING) if behavior or layout changed.

## Related issues

<!-- e.g. Closes #NN -->
