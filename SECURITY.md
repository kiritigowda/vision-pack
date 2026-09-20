# Security Policy

## Reporting a vulnerability

Please do **not** report security vulnerabilities through public GitHub issues, pull
requests, or discussions.

Instead, report them privately through GitHub's security advisory workflow:

1. Go to the repository's **Security** tab.
2. Select **Report a vulnerability** (this opens a private advisory visible only to
   maintainers).
3. Include a description of the issue, the affected component, reproduction steps, and any
   relevant logs or proof-of-concept.

You will receive an acknowledgement, and the maintainers will coordinate a fix and
disclosure timeline with you privately.

Because vision-pack aggregates upstream ROCm libraries and third-party dependencies, a
report may be forwarded to the relevant upstream project (e.g. MIVisionX, rocAL, protobuf)
when the root cause lives there.

## CVE scanning

Bundled third-party dependencies (protobuf, libjpeg-turbo, lmdb, libsndfile) are
scanned for known CVEs as part of the CI pipeline. See
[#33](https://github.com/kiritigowda/vision-pack/issues/33) for progress on
automated CVE scanning.

## Supported versions

vision-pack is pre-release software; no released versions are formally supported yet. A
supported-versions table will be added here once stable releases begin.

| Version | Status | Notes |
|---|---|---|
| 0.1.0 | Pre-release | Initial release |
