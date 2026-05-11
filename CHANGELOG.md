## 1.0.0

- Initial release.
- Transparent HTTP proxy using `dart:io` `HttpServer` + `HttpClient` — no extra HTTP dependencies.
- Captures every JSON response and stores it in a `RouteStore`, keyed by `method:path`.
- Deduplication: second capture of the same endpoint is silently discarded; first capture wins.
- Binary and oversized (>10 MB) responses are skipped and logged.
- Writes `dio_mock_interceptor`-compatible YAML (or JSON with `--format json`) on `Ctrl+C`.
- Atomic write via `.tmp` rename — a crash cannot leave a partial output file.
- CLI flags: `--target`, `--port`, `--out`, `--format`, `--filter`, `--insecure`, `--capture-errors`, `--append`, `--version`, `--help`.
