# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet.

## [1.0.0] — 2026-08-16

First public release.

### Added

- `AppleScriptObject`, describing a script, its expected return type, and the variables that fill its `$key` placeholders. Variables can be set when the object is declared or supplied at call time, with runtime values winning on conflict.
- Automatic escaping of every substituted `String`, so paths, folder names and filenames arrive as data rather than as code. Numbers and booleans render as bare AppleScript literals.
- `AppleScriptRawValue`, to opt a value out of escaping when it is genuinely AppleScript source, such as a list or record built by the caller.
- `executeAppleScript(_:with:)`, running a script through `NSAppleScript` and parsing the result into the type the script declares — `Int`, `String`, `Bool`, list, flat record, or JSON. Calls arriving off the main thread are marshalled onto the main queue, since `NSAppleScript` is not thread-safe.
- `executeAppleScriptViaCommandLine(_:with:)`, running the same script through `/usr/bin/osascript` in a subprocess.
- `AppleScriptError`, covering compilation failure, unreadable output, execution errors, and a catch-all case for your own messages.
- `requestAutomationPermission(for:activating:)` and `resetAutomationPermission(for:)`, for triggering and clearing the system Automation prompt.
- `AppleScriptBridge.logHandler`, a closure controlling where the package logs prepared script sources. Prints in `DEBUG` builds by default; assign `nil` to silence.
- `String` and `URL` helpers: `appleScriptStringEscaped`, `parseSimpleAppleScriptRecord()`, `parseJSONStringFromAppleScript()`, `toPOSIXPath()` and `toHFSPath()`.

### Notes

- Requires macOS 13 or later. No dependencies beyond Foundation and Cocoa.
- Ships in Swift 5 language mode. `AppleScriptObject` carries `[String: Any]`, which is not `Sendable`; a strict-concurrency redesign is planned for 2.0.
- An app using this package cannot be sandboxed and so cannot ship on the Mac App Store. Developer ID signing and notarization are unaffected.

[Unreleased]: https://github.com/fredsimard/SwiftAppleScriptBridge/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/fredsimard/SwiftAppleScriptBridge/releases/tag/v1.0.0
