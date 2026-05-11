# MockBeam Record — Product Requirements Document (PRD)

**Author:** Anuj Gupta
**Version:** 2.0 (revised scope)
**Date:** May 2026
**Status:** Draft — pre-build
**Target ship:** 1 week from start

---

## 0. Why This Document Exists (Revision Note)

The original MockBeam PRD proposed a full Flutter package + CLI that intercepts HTTP calls and serves mock responses from YAML config.

**That idea was killed after competitive research.**

The following packages already solve that problem adequately on pub.dev:

| Package | What it does |
|---------|-------------|
| `dio_mock_interceptor` | Intercepts dio calls, serves from JSON files |
| `dio_mocked_responses` | Fork of above, adds personas, templates, request history |
| `mockzilla` | Local mock HTTP server with desktop GUI |
| `flutter_api_mock_server` | Path/method matching with delay simulation |
| `flutter_mock_web_server` | Mock web server for test isolation |

Building another one of these would be rebuilding what already exists. That is not a portfolio piece — it is a redundancy.

**The gap:** None of these tools can capture real API responses automatically. Every one of them requires the developer to write mock responses by hand. This is the problem MockBeam Record solves.

---

## 1. Problem & Motivation

### 1.1 The problem

Every Flutter mock package on pub.dev shares the same fundamental flaw: **you have to write the mock responses yourself.**

This means:

- You manually inspect network responses in DevTools or Postman
- You copy-paste JSON into mock config files
- When the real API changes, your mocks silently become stale
- Any edge-case response shape you forgot to copy becomes a bug you discover late

The information-theoretic reality is that the real API already has all the responses. There is no reason to re-type them.

### 1.2 The solution

MockBeam Record is a **Dart CLI tool** that acts as a transparent HTTP proxy between your Flutter app and your real backend. You run your app normally for a few minutes. MockBeam captures every request and response and writes them as a YAML file compatible with `dio_mock_interceptor` — the most popular mock package on pub.dev.

You never write a mock response again. You record it once.

### 1.3 Why this is the right scope

The original PRD tried to own the entire mock workflow — interception, config format, CLI, hot reload. That is a 3-week project competing against established packages.

This PRD owns **one step in the workflow** — the recording step — and integrates with what already exists. That is a 1-week project that fills a genuine gap.

The competitive moat is not "another mock package." It is "the tool that feeds all the other mock packages."

### 1.4 Why this is good portfolio material

Building a recording proxy demonstrates:

- **Network programming:** HTTP proxy implementation using `dart:io`'s `HttpServer`
- **Protocol understanding:** Correctly forwarding headers, bodies, status codes, content types
- **Developer tooling instinct:** Identifying a gap in an existing ecosystem and filling it precisely
- **Competitive research:** Knowing what exists before building — the PRD explicitly documents this
- **Ecosystem thinking:** Outputting to an existing format (`dio_mock_interceptor` JSON/YAML) rather than inventing a new one

The last point matters for interviews. "I researched what already existed, found the gap, integrated with the ecosystem rather than competing with it" is a senior engineering instinct coming from a 0–2 year engineer. That is memorable.

---

## 2. Target User & Use Cases

### 2.1 Primary user

Flutter developers who are already using (or want to use) `dio_mock_interceptor` or similar packages, and are tired of writing mock responses by hand.

In v1, the primary user is me (Anuj) — dogfooding on my own projects.

### 2.2 Use cases

- **U1 — Bootstrap a new project:** Backend API exists but isn't stable. Developer runs MockBeam Record for 10 minutes, exercises all the screens, gets a complete `recorded.yaml`. From that point, development continues offline with accurate mock data.
- **U2 — Reproduce a bug:** A specific backend response triggered a crash. Developer can't reproduce it on demand. But they captured it with MockBeam Record last week. The mock is in `recorded.yaml`. They iterate on the fix against the exact response shape.
- **U3 — Demo prep:** Upcoming demo needs to work without network. Developer records a clean set of responses against staging, enables mock mode, demo runs perfectly offline.
- **U4 — Onboarding:** New team member can't get API keys yet. Senior dev shares `recorded.yaml`. New dev runs the full app on day one.
- **U5 — Test fixture generation:** QA engineer wants integration test fixtures. MockBeam Record produces them from a real session rather than hand-crafting them.

### 2.3 Out of scope users (v1)

- Non-Flutter Dart projects (possible in v2, not the target)
- Teams needing a shared remote mock server
- Projects not using HTTP (WebSocket, gRPC)

---

## 3. Goals & Non-Goals

### 3.1 Goals (v1)

| # | Goal | Success criterion |
|---|------|-------------------|
| G1 | Transparent HTTP proxy | Every request forwarded correctly; app behavior identical to direct API call |
| G2 | Response capture | Every intercepted response written to output YAML |
| G3 | `dio_mock_interceptor` compatibility | Output YAML loads correctly into `dio_mock_interceptor` without modification |
| G4 | HTTPS support | Works with HTTPS targets (certificate bypass mode for dev) |
| G5 | Installable via pub global | `dart pub global activate mockbeam_record` works |
| G6 | Single-command startup | `mockbeam record --target https://api.myapp.com` is all you need |
| G7 | Deduplication | Recording the same endpoint twice does not create duplicate entries |
| G8 | Published on pub.dev | Live, installable, with a pub score ≥ 100 |

### 3.2 Non-goals (explicitly NOT in v1)

- ❌ The interception/serving side (that's `dio_mock_interceptor`'s job)
- ❌ HTTPS certificate generation or CA injection (developer accepts the cert manually or uses `--insecure`)
- ❌ Stateful response sequences
- ❌ WebSocket recording
- ❌ gRPC recording
- ❌ Binary response bodies (images, PDFs) — logged as skipped, not captured
- ❌ GUI or web dashboard
- ❌ Real-time preview of captured responses
- ❌ Filtering by status code
- ❌ Authentication token scrubbing (v2 concern)
- ❌ Multi-target proxying (one `--target` per session)

---

## 4. User Flow

### 4.1 Install

```bash
dart pub global activate mockbeam_record
```

### 4.2 Record session

```bash
mockbeam record --target https://api.myapp.com --port 8080 --out mocks/recorded.yaml
```

Terminal output:

```
MockBeam Record v1.0.0
Proxying https://api.myapp.com → localhost:8080
Output: mocks/recorded.yaml

Waiting for requests... (Ctrl+C to stop and save)

  ✓  GET  /users/me           200  142ms
  ✓  GET  /users/1/posts      200   89ms
  ✓  POST /auth/refresh       200  201ms
  ✓  GET  /notifications      200   67ms
  ⚠  GET  /avatar.png         200  [binary — skipped]
  ✓  GET  /notifications      200  [duplicate — skipped]

^C
Stopping... 4 routes captured.
Wrote mocks/recorded.yaml
```

### 4.3 Use output with dio_mock_interceptor

The output YAML is immediately usable:

```yaml
# Generated by MockBeam Record v1.0.0
# Target: https://api.myapp.com
# Recorded: 2026-05-08T14:32:00Z

- path: /users/me
  method: GET
  statusCode: 200
  data:
    id: 1
    name: "Anuj Gupta"
    email: "anuj@example.com"

- path: /users/1/posts
  method: GET
  statusCode: 200
  data:
    - id: 101
      title: "First post"
    - id: 102
      title: "Second post"

- path: /auth/refresh
  method: POST
  statusCode: 200
  data:
    token: "eyJhbGciOiJIUzI1NiJ9..."
    expiresIn: 3600
```

Developer drops this in their `assets/mock/` folder, wires up `dio_mock_interceptor`, done.

### 4.4 Configuring the Flutter app to point at the proxy

This is a one-time change during recording sessions. Developer sets the base URL to `http://localhost:8080` while MockBeam is running. The README covers this with a copy-paste snippet:

```dart
// In development: point at MockBeam proxy
const baseUrl = String.fromEnvironment('BASE_URL', defaultValue: 'https://api.myapp.com');
```

```bash
flutter run --dart-define=BASE_URL=http://localhost:8080
```

No code changes. No conditional logic. Just a build flag.

---

## 5. Functional Requirements

### 5.1 Proxy core

| ID | Requirement | Priority |
|----|-------------|----------|
| F-P1 | Start HTTP server on specified port (default 8080) | P0 |
| F-P2 | Forward all incoming requests to `--target` base URL | P0 |
| F-P3 | Preserve method, path, query string, headers, and body exactly | P0 |
| F-P4 | Return the real response to the client unchanged | P0 |
| F-P5 | Support HTTPS targets with `--insecure` flag (skip cert verification) | P0 |
| F-P6 | Handle concurrent requests (don't serialize) | P1 |
| F-P7 | Log each request to stdout with method, path, status, duration | P0 |

### 5.2 Capture & output

| ID | Requirement | Priority |
|----|-------------|----------|
| F-C1 | Capture method, path, status code, and JSON response body | P0 |
| F-C2 | Write captured routes to YAML on Ctrl+C (SIGINT) | P0 |
| F-C3 | Deduplicate: if method+path already captured, skip subsequent captures | P0 |
| F-C4 | Skip binary responses (Content-Type not `application/json`); log as skipped | P0 |
| F-C5 | Skip non-2xx responses by default; `--capture-errors` flag captures them too | P1 |
| F-C6 | Write header comment to YAML with target URL and timestamp | P1 |
| F-C7 | `--append` flag: merge new routes into an existing YAML file rather than overwrite | P1 |
| F-C8 | `--filter` flag: only capture paths matching a glob pattern (e.g. `/api/*`) | P1 |

### 5.3 Output format compatibility

| ID | Requirement | Priority |
|----|-------------|----------|
| F-O1 | Default output format matches `dio_mock_interceptor` JSON schema | P0 |
| F-O2 | `--format json` flag outputs JSON instead of YAML (for packages that prefer JSON) | P1 |
| F-O3 | Output passes `dio_mock_interceptor`'s own validation (manual test) | P0 |

### 5.4 CLI UX

| ID | Requirement | Priority |
|----|-------------|----------|
| F-L1 | `mockbeam record --target <url>` — start recording session | P0 |
| F-L2 | `--port <n>` — local proxy port (default 8080) | P0 |
| F-L3 | `--out <path>` — output file path (default `mocks/recorded.yaml`) | P0 |
| F-L4 | `--insecure` — skip TLS certificate verification for HTTPS targets | P0 |
| F-L5 | `--capture-errors` — also capture 4xx and 5xx responses | P1 |
| F-L6 | `--append` — merge into existing output file | P1 |
| F-L7 | `--filter <glob>` — only capture matching paths | P1 |
| F-L8 | `--format json\|yaml` — output format (default yaml) | P1 |
| F-L9 | `mockbeam --version` | P1 |
| F-L10 | `mockbeam --help` with full usage | P1 |

### 5.5 pub.dev quality

| ID | Requirement | Priority |
|----|-------------|----------|
| F-Q1 | All public API has `///` doc comments | P0 |
| F-Q2 | `dart analyze` passes zero warnings | P0 |
| F-Q3 | Unit tests for: deduplication, binary skip, path forwarding logic, YAML serialization | P0 |
| F-Q4 | `example/` folder or README with a runnable example | P0 |
| F-Q5 | `CHANGELOG.md` and `LICENSE` (MIT) present | P0 |
| F-Q6 | pub score ≥ 100 at publish time | P1 |

---

## 6. System Architecture

### 6.1 How it works

```
┌─────────────────────────────────────────────────────────────┐
│                    Developer's machine                      │
│                                                             │
│  ┌─────────────┐    HTTP to      ┌─────────────────────┐   │
│  │ Flutter App │─────localhost───►│  MockBeam Proxy     │   │
│  │             │    :8080        │                     │   │
│  └─────────────┘                 │  ┌───────────────┐  │   │
│                                  │  │ Request Store │  │   │
│                                  │  │ (dedup table) │  │   │
│                                  │  └───────────────┘  │   │
│                                  │          │           │   │
│                                  └──────────┼───────────┘   │
│                                             │               │
│                                    Forward request          │
│                                             │               │
└─────────────────────────────────────────────┼───────────────┘
                                              │
                                    ┌─────────▼──────────┐
                                    │   Real Backend     │
                                    │ https://api.my.com │
                                    └─────────┬──────────┘
                                              │
                                    Real response
                                              │
┌─────────────────────────────────────────────┼───────────────┐
│                                             │               │
│                                  ┌──────────▼───────────┐   │
│                                  │  MockBeam Proxy      │   │
│  ┌─────────────┐  Real response  │                      │   │
│  │ Flutter App │◄────────────────│  1. Capture if JSON  │   │
│  │  (unaware)  │                 │  2. Deduplicate      │   │
│  └─────────────┘                 │  3. Return to app    │   │
│                                  └──────────────────────┘   │
│                                             │               │
│                              On Ctrl+C: write YAML          │
│                                             ▼               │
│                                  mocks/recorded.yaml        │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 Component breakdown

**`ProxyServer`** — the `HttpServer` that receives incoming Flutter app requests. Binds to `localhost:port`. For each request, delegates to `RequestForwarder`.

**`RequestForwarder`** — takes an incoming `HttpRequest`, reconstructs it against the target base URL, sends it using `dart:io`'s `HttpClient`, receives the response, and pipes it back to the Flutter app. This is the core of the proxy.

**`ResponseCapture`** — inspects each response. If Content-Type is `application/json`, parses the body and hands it to `RouteStore`. Otherwise marks the request as skipped.

**`RouteStore`** — in-memory table of captured routes keyed by `method:path`. Handles deduplication. On SIGINT, serializes to YAML via `RouteSerializer`.

**`RouteSerializer`** — converts `RouteStore` contents to `dio_mock_interceptor`-compatible YAML or JSON. Handles the header comment (target URL, timestamp).

**`CLI`** — entry point. Parses args with `package:args`, validates them, wires up the components, registers SIGINT handler.

### 6.3 Folder structure

```
mockbeam_record/
├── bin/
│   └── mockbeam_record.dart     # CLI entry point
├── lib/
│   ├── mockbeam_record.dart     # Public API (for programmatic use)
│   └── src/
│       ├── proxy_server.dart
│       ├── request_forwarder.dart
│       ├── response_capture.dart
│       ├── route_store.dart
│       ├── route_serializer.dart
│       └── cli.dart
├── test/
│   ├── route_store_test.dart
│   ├── route_serializer_test.dart
│   └── response_capture_test.dart
├── pubspec.yaml
├── README.md
├── CHANGELOG.md
└── LICENSE
```

### 6.4 The forwarding logic in detail

This is the engineering heart of the tool. Getting it right matters.

```dart
// Pseudocode — the real implementation handles errors, timeouts, streaming

Future<void> forwardRequest(HttpRequest incoming, Uri targetBase) async {
  // 1. Build target URL
  final targetUri = targetBase.replace(
    path: incoming.uri.path,
    query: incoming.uri.query,
  );

  // 2. Open outgoing request
  final client = HttpClient()..badCertificateCallback = (_, __, ___) => insecure;
  final outgoing = await client.openUrl(incoming.method, targetUri);

  // 3. Forward headers (strip hop-by-hop headers)
  incoming.headers.forEach((name, values) {
    if (!_hopByHopHeaders.contains(name.toLowerCase())) {
      outgoing.headers.set(name, values);
    }
  });

  // 4. Forward body
  await incoming.pipe(outgoing);

  // 5. Get response
  final response = await outgoing.close();

  // 6. Capture if JSON
  final body = await utf8.decodeStream(response);
  capture(incoming.method, incoming.uri.path, response.statusCode, body, response.headers);

  // 7. Return to app
  incoming.response.statusCode = response.statusCode;
  response.headers.forEach((name, values) => incoming.response.headers.set(name, values));
  incoming.response.write(body);
  await incoming.response.close();
}
```

**Hop-by-hop headers** — these must be stripped before forwarding: `Connection`, `Keep-Alive`, `Transfer-Encoding`, `TE`, `Trailer`, `Upgrade`, `Proxy-Authorization`, `Proxy-Authenticate`. Forwarding these incorrectly breaks the proxied connection. This is the most common proxy implementation bug and is worth calling out explicitly in an interview.

---

## 7. Technical Decisions & Tradeoffs

| Decision | Choice | Why | Alternative considered |
|----------|--------|-----|------------------------|
| Output format | `dio_mock_interceptor` YAML | Most popular Flutter mock package; zero extra work for the user | Inventing a new format (user would need a new interception package too) |
| Proxy approach | `dart:io` HttpServer + HttpClient | No dependencies; sufficient for single-machine dev tool | `package:shelf` (adds a dependency for no real benefit) |
| HTTPS handling | `--insecure` flag, no cert injection | Cert injection (into Android's trust store) is complex, fragile, platform-specific | Cert injection (pushed to v2) |
| Dedup key | method + path (ignores query string) | Query strings vary per call; same endpoint is the same mock | Full URL dedup (would produce duplicates for paginated endpoints like `/posts?page=1`, `/posts?page=2`) |
| Save trigger | SIGINT (Ctrl+C) | Natural "I'm done recording" signal; avoids partial writes | Auto-save every N seconds (more complex, risks partial YAML on crash) |
| Binary bodies | Skip, log warning | Base64-encoding images into YAML is useless for mock purposes | Capture as base64 (bloats file, confuses `dio_mock_interceptor`) |
| Concurrency | Async parallel forwarding | Requests should not block each other | Sequential (would make the app feel slow during recording) |

---

## 8. Edge Cases & Failure Modes

| Case | Designed behavior |
|------|-------------------|
| Target URL is unreachable | Proxy returns 502 to the app; logs `[MockBeam] Cannot reach target: connection refused` |
| Response body is not valid JSON | Treated as binary; skipped; logged as `[skipped — not JSON]` |
| Same endpoint called with different response bodies | First capture wins; subsequent are deduped; logs `[duplicate — skipped]` |
| Ctrl+C before any requests captured | Writes empty `routes: []` YAML; logs `0 routes captured` |
| Output directory doesn't exist | Creates it; does not fail |
| Port already in use | Clear error: `Port 8080 is already in use. Try --port 8081` |
| Response body too large (>10 MB) | Skip and warn: `[skipped — body too large (12.4 MB)]` |
| Hop-by-hop headers forwarded incorrectly | Stripped before forwarding (see §6.4) — this is why it's documented explicitly |
| Flutter app sends request to wrong host | Proxy forwards blindly to `--target`; path is preserved; irrelevant headers are ignored |
| SIGINT during write | File write is atomic (write to `.tmp`, then rename); partial files not possible |

---

## 9. Security Considerations

MockBeam Record is a **development-only tool**. It is not intended for use in CI, staging, or production environments.

### 9.1 What the `--insecure` flag means

With `--insecure`, MockBeam bypasses TLS certificate verification when connecting to the target. This is intentional for local development against self-signed or staging certs. It must never be used against production endpoints over untrusted networks.

The README will include a prominent warning:

> ⚠️ `--insecure` disables TLS verification. Only use this on trusted networks against non-production endpoints.

### 9.2 Sensitive data in recorded responses

Recorded YAML files may contain authentication tokens, personal data, or other sensitive values from real API responses. The README will note:

> MockBeam Record does not scrub sensitive values from captured responses. Do not commit `recorded.yaml` to version control without reviewing its contents. Add `mocks/recorded.yaml` to `.gitignore`.

Token scrubbing (replacing values matching patterns like `Bearer ...`) is a v2 feature.

### 9.3 What MockBeam does NOT protect against

- Developers committing raw API responses (including tokens) to git
- Recording against production APIs on shared networks
- Man-in-the-middle attacks on the recording session itself (this is a local dev tool; that threat model is out of scope)

---

## 10. One-Week Build Timeline

Each day ends with something runnable — not just infrastructure.

### Day 1 — Skeleton proxy

- Project scaffold, `pubspec.yaml`, folder structure
- `HttpServer.bind` + basic request logging (method, path, status)
- Hardcode target URL; no capture yet
- **Milestone:** `curl http://localhost:8080/users/me` returns the real API response. Proxy is transparent.

### Day 2 — Forwarding correctness

- Proper header forwarding with hop-by-hop stripping
- Body forwarding (including POST bodies)
- HTTPS target support with `--insecure`
- **Milestone:** Flutter app pointed at proxy behaves identically to direct API. No broken requests.

### Day 3 — Capture + dedup

- `ResponseCapture` — detect JSON, parse body
- `RouteStore` — in-memory table with method+path dedup
- Log captured vs skipped routes to stdout
- **Milestone:** Terminal shows live capture log. Correct routes appear, duplicates are skipped.

### Day 4 — YAML output

- `RouteSerializer` — serialize `RouteStore` to `dio_mock_interceptor` YAML
- SIGINT handler — write on Ctrl+C
- `--out` flag
- Atomic write (tmp + rename)
- **Milestone:** Full session → Ctrl+C → `recorded.yaml` opens in `dio_mock_interceptor` with zero modification.

### Day 5 — CLI polish + P1 flags

- `--append`, `--capture-errors`, `--filter`, `--format json`
- `--version`, `--help`
- Port conflict error handling
- Output directory creation
- **Milestone:** All P0 + P1 requirements pass.

### Day 6 — pub.dev prep

- `///` doc comments on all public API
- Unit tests: `RouteStore` dedup, `RouteSerializer` output format, `ResponseCapture` binary detection
- `dart analyze` clean
- `CHANGELOG.md`, `LICENSE`
- **Milestone:** `dart pub publish --dry-run` passes.

### Day 7 — Publish + portfolio

- Publish to pub.dev
- README with: 30-second pitch, terminal GIF, quickstart, integration example with `dio_mock_interceptor`, known limitations
- **Milestone:** Live on pub.dev. Link goes in the resume.

---

## 11. Definition of Done (v1)

- [ ] Published on pub.dev, installable via `dart pub global activate mockbeam_record`
- [ ] All P0 requirements in §5 pass manual test
- [ ] `dart analyze` zero warnings
- [ ] Unit tests pass for: dedup, binary skip, YAML serialization, path forwarding
- [ ] Output YAML loads into `dio_mock_interceptor` without modification (manual test)
- [ ] Works with both HTTP and HTTPS targets
- [ ] README contains: pitch, GIF, quickstart, `dio_mock_interceptor` integration example, `.gitignore` warning
- [ ] Public GitHub repo with MIT license

---

## 12. The Interview Pitch

When an interviewer asks about this project:

> *"I was looking for a portfolio project in the Flutter developer tooling space. Before building anything, I did competitive research on pub.dev and found five packages that already solve the HTTP mock problem — `dio_mock_interceptor`, `mockzilla`, and a few others. But I noticed none of them could capture real API responses automatically. Every one requires you to write mock data by hand.*
>
> *So I built MockBeam Record — a Dart CLI proxy tool that sits between your Flutter app and your real backend, captures every JSON response, deduplicates by endpoint, and writes a YAML file that drops straight into `dio_mock_interceptor`.*
>
> *The interesting engineering was in the proxy layer — correctly stripping hop-by-hop headers before forwarding, handling concurrent requests without serializing them, and making the write operation atomic so you never get a partial YAML file on crash. It's published on pub.dev."*

That pitch is 90 seconds. It shows competitive awareness, ecosystem thinking, and specific technical depth. It is better than any pitch for a generic mock package would have been.

---

## Appendix A — Glossary

- **HTTP proxy:** A server that sits between a client and a destination server, forwarding requests and responses. MockBeam Record is a forward proxy.
- **Hop-by-hop headers:** HTTP headers that are meaningful only for a single transport-level connection and must not be forwarded by proxies. Examples: `Connection`, `Transfer-Encoding`, `Upgrade`.
- **`dio_mock_interceptor`:** The most widely used Flutter package for mocking API responses during development. Uses JSON/YAML config files. MockBeam Record outputs to its format.
- **Deduplication:** The process of discarding a captured route because an identical method+path combination was already captured in the current session.
- **SIGINT:** The Unix signal sent when the user presses Ctrl+C. MockBeam uses this as the trigger to write the output file.
- **Atomic write:** Writing to a temporary file and then renaming it to the final path. Ensures the output file is never partially written if the process crashes during a write.
- **pub.dev:** The official Dart and Flutter package registry. Packages are installable globally via `dart pub global activate`.
- **pub score:** Automated quality score (0–140) assigned by pub.dev based on documentation, static analysis, platform support, and test coverage.
