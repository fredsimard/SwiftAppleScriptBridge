# Security policy

## Supported versions

The latest 1.x release is the only supported version. Fixes go into a new patch release rather than being backported.

| Version | Supported |
|---|---|
| 1.x | ✅ |
| < 1.0 | ❌ |

## Reporting a vulnerability

Please report privately rather than opening a public issue: use [**Report a vulnerability**](https://github.com/fredsimard/SwiftAppleScriptBridge/security/advisories/new) on the Security tab, which opens a private advisory only you and I can see.

This is a spare-time project, so expect a first response within a week or so. If a report holds up, I'll fix it, credit you unless you'd rather I didn't, and publish an advisory alongside the release.

Please include the input that triggers it, the resulting AppleScript source (`preparedScript(with:)` shows you exactly what would run), and what an attacker gains.

## What counts as a vulnerability

The package's central security claim is that **values substituted into a script cannot escape their string literal and become code**. Anything that breaks that claim is a vulnerability. Concretely:

- Input that, passed as a `String` variable, terminates its AppleScript literal and executes attacker-controlled commands.
- Any gap in `appleScriptStringEscaped` — text it fails to neutralise inside a `"..."` literal.
- A value type reaching `substitution(for:)` that gets inserted unescaped when it shouldn't be.
- Result parsing (`parseSimpleAppleScriptRecord()`, `parseJSONStringFromAppleScript()`) crashing or corrupting memory on malformed input from a controlled application.

## What doesn't

- **`AppleScriptRawValue` executing what you put in it.** That's what it's for. Wrapping unvalidated input in it is a bug in the calling app, and the documentation says so in several places.
- **Scripts you wrote doing what you wrote.** The package doesn't sandbox or inspect your AppleScript; it compiles and runs it.
- **What the controlled application does** once your script tells it to. That's between your script and that app.
- **Automation permissions.** Whether macOS lets your app drive another one is TCC's decision, not this package's.
- **The absence of sandboxing.** An app using this package can't be sandboxed — that's a documented consequence of using Apple events, not a flaw here.
- **`executeAppleScriptViaCommandLine(_:with:)` not detecting script errors.** A documented limitation. Reports that it should throw are welcome as issues, not as advisories.
