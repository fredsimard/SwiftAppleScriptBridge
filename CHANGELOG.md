# Changelog

All notable changes to this project are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Nothing yet.

## [1.2.0] — 2026-08-29

New API, all of it opt-in: the default path is unchanged. One caveat before you upgrade — `AppleScriptReturnType` and `AppleScriptError` each gained a case, so code that switches over either exhaustively, without a `default`, stops compiling until the new case is handled.

### Added

- A `.wildCard` return type, for the properties that answer with a different *type* depending on state — the `value` of a cell in Numbers is a number, a date, text, a boolean, or `missing value`, the last one meaning the cell is empty. Every other return type coerces that distinction away before Swift sees it. `.wildCard` returns an `AppleScriptValue` built from the Apple event descriptor instead, so the type can be switched on. Closes [#5](https://github.com/fredsimard/SwiftAppleScriptBridge/issues/5).
  - `AppleScriptValue` decodes numbers, text, booleans, dates, files, `missing value`, application-defined constants, and lists and records, the last two recursively. Anything else arrives as `.unknown`, carrying the descriptor untouched so nothing is lost. Its `init(descriptor:)` is public, for descriptors obtained some other way.
  - Constants carry their raw `FourCharCode`: what `'autp'` means is defined by the target application's dictionary, not by AppleScript, so there is no general mapping to hand the caller. `missing value` is the exception and has a case of its own.
  - Record keys come through as written only when AppleScript did not recognize them as its own terminology. `{name:"Roger", age:42}` decodes as `["pnam": .string("Roger"), "age": .int(42)]`, since `name` compiles to the `'pnam'` property before the script ever runs.
  - Integers are read at the width their descriptor declares rather than through `int32Value`, which answers `0` for anything wider than 32 bits.
- `String.appleScriptFourCharCode` and `String.init(appleScriptFourCharCode:)`, converting between a four-character code and its text, so an `AppleScriptValue.constant` can be compared against a code from an application's dictionary without building it by hand.
- `AppleScriptError.unsupportedReturnType(AppleScriptReturnType)`, thrown when an execution method cannot produce the declared type.

### Notes

- `.wildCard` works through `executeAppleScript(_:with:)` only. `osascript` prints its result as text, so the descriptor carrying the actual type is gone before `executeAppleScriptViaCommandLine(_:with:)` could read it; that method throws `.unsupportedReturnType` before launching the process, so the script does not run.

## [1.1.0] — 2026-08-19

### Added

- Swift collections are now rendered as their AppleScript equivalents on substitution: an `Array` becomes a list, a `Dictionary` becomes a record, and the two nest, so an array of dictionaries arrives as a list of records. Elements are escaped by the same rules as any other value, so building AppleScript source by hand and wrapping it in `AppleScriptRawValue` is no longer the only way to pass a list. Both render as bare literals, written `$key` rather than `"$key"`. Closes [#1](https://github.com/fredsimard/SwiftAppleScriptBridge/issues/1).
  - Record keys that are not plain AppleScript identifiers — keys holding spaces or punctuation, and AppleScript's reserved words — are vertical-bar quoted (`{|first name|:"Roger"}`), which is the only way such a key can be written. Keys that *are* plain identifiers are left bare, so a term the target application defines keeps its meaning.
  - Dictionary keys are sorted when rendered, so the same dictionary always produces the same script source. A key that is not a `String` is described first, which is what a dictionary bridged from Objective-C or from `JSONSerialization` needs.
  - An empty dictionary renders as `{}`, which is also how AppleScript writes an empty list. The script decides which it is.

### Changed

- An `Array` or `Dictionary` passed as a variable used to fall through to `String(describing:)` and arrive as text such as `["a", "b"]`. It now arrives as a real AppleScript list or record. The public API is unchanged and nothing stops compiling on the Swift side, but a script written against the old text form has to be updated — that output was almost certainly a bug rather than something to depend on.
- A collection substituted into a *quoted* placeholder (`"$key"`) now produces a syntax error rather than text, since the rendered literal carries its own quotation marks: `"{"a", "b"}"`. Write these placeholders bare, as `$key`. The failure is loud and happens at compile time, before the script runs.

## [1.0.1] — 2026-08-16

Six fixes from a full audit of the package. The public API is unchanged, but three of them change what an existing call returns in cases where the old result was wrong.

### Fixed

- `executeAppleScriptViaCommandLine(_:with:)` returned `false` for every `.bool` script. `osascript` prints booleans as `true` and `false`, which the integer parsing read as zero. Both forms are now accepted.
- `executeAppleScriptViaCommandLine(_:with:)` deadlocked on output larger than the pipe buffer, around 64 KB — a `.json` listing of a large folder reaches that easily. The pipe is now drained before the process is waited on.
- Variable substitution rescanned text it had already substituted, so a value containing a placeholder name was rewritten by a later variable: a file named `$folderPath.txt` passed as `folderPath` had that variable's value spliced into its name. The script is now walked once.
- Numbers arriving as `NSNumber`, from `JSONSerialization` or from Objective-C, were substituted as `true` rather than as their value, because an `NSNumber` bridges to `Bool` whatever it holds. `Float` and `UInt` now render as numbers too, instead of as escaped text.
- `toHFSPath()` prepended the startup disk name to every path, so a file on any other volume converted to a path pointing at nothing. The volume name and mount point are now read from the path itself, which also covers disk images and network shares. That requires the path to exist; `nil` comes back otherwise.
- `resetAutomationPermission(for:)` reported success whenever `tccutil` launched, ignoring its exit status.

### Added

- `Examples/AppleScripts.swift`, showing the one-file-of-scripts layout with a script for every return type, the three placeholder forms, a raw AppleScript list, and the Swift call site for each. CI builds it as a consumer package so it cannot rot.
- README section on Swift 6 language mode. `AppleScriptObject` is not `Sendable`, so declaring scripts as `static let` needs `nonisolated(unsafe)` there. Removing that requirement is tracked in [#2](https://github.com/fredsimard/SwiftAppleScriptBridge/issues/2).
- `Documentation/API.md`, a reference for every public symbol.
- `CONTRIBUTING.md`, `SECURITY.md`, and issue and pull request templates.

### Changed

- Dropped four redundant `?? nil` coalescings in `executeAppleScript(_:with:)`, where the expression was already optional and the return type is `Any?`. Same results, same types.
- SwiftLint now fails the build on any violation, with the rules that conflict with the codebase's deliberate style disabled and annotated.
- Documentation corrections across `README.md`, `Documentation/API.md` and the in-code doc comments: the throws list for `executeAppleScript(_:with:)`, the omitted `[String: Any]` return case, the record parser's key rule, how `.bool` results are read, and a warning that the command-line method passes the script as an argument visible to `ps`.

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

[Unreleased]: https://github.com/fredsimard/SwiftAppleScriptBridge/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/fredsimard/SwiftAppleScriptBridge/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/fredsimard/SwiftAppleScriptBridge/compare/v1.0.1...v1.1.0
[1.0.1]: https://github.com/fredsimard/SwiftAppleScriptBridge/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/fredsimard/SwiftAppleScriptBridge/releases/tag/v1.0.0
