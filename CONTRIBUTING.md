# Contributing

Read our [Code of Conduct](CODE_OF_CONDUCT.md) before participating.
For vulnerabilities, use the private [security reporting policy](SECURITY.md).

## Build and checks

Use a Flutter stable SDK, as in `.github/workflows/ci.yml`. From the repository root:

```sh
bash scripts/ci_pub_get.sh
python3 -m unittest discover -s scripts/tests
flutter analyze --no-pub
flutter test --no-pub --concurrency=2
flutter build apk --debug
```

Release configuration is documented in [README.md](README.md); use local development settings for development. Do not include signing material or service credentials in a PR.

## Branch and pull request flow

1. Search existing issues and PRs before starting work.
2. Create a focused branch from current `main` (use a fork when available).
3. Add or update relevant tests for behavior changes and run the checks above.
4. Open a PR describing what changed, why, and the checks you ran. Include `Refs #N` for the relevant issue.
5. Address review feedback before a maintainer merges the PR.

Documentation-only changes require a rendered preview and link checks. State any checks you could not run; do not label skipped checks as passing. Keep secrets and personal information out of commits, logs, and screenshots.
