# SwiftAppleScriptBridge

A small, typed bridge between Swift and AppleScript for macOS applications.

It wraps `NSAppleScript` with three things that are tedious to get right by hand:

- **Templated scripts.** Write AppleScript once with `$key` placeholders and fill them at call time.
- **Automatic escaping.** Every substituted `String` is escaped before it reaches the script, so a folder named `Client "A"\B` cannot terminate a string literal and inject AppleScript.
- **Typed results.** Declare what a script returns — `Int`, `String`, `Bool`, a list, a flat record, or JSON — and get a parsed Swift value back.

Requires macOS 13 or later. No dependencies.

> **Before you adopt it:** an app using this package cannot be sandboxed and cannot be distributed on the Mac App Store. Developer ID signing and notarization work normally. See [Distribution](#️-distribution-read-this-before-you-adopt-the-package).

## Installation

In Xcode: **File ▸ Add Package Dependencies…**, then paste the repository URL.

Or in a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/fredsimard/SwiftAppleScriptBridge", from: "1.0.0")
]
```

## Usage

```swift
import SwiftAppleScriptBridge

let countOpenWindows = AppleScriptBridge.AppleScriptObject(
    name: "countOpenWindows",
    returnType: .int,
    script: """
        tell application id "com.apple.finder"
            return count of windows
        end tell
    """
)

let count = try AppleScriptBridge.executeAppleScript(countOpenWindows) as? Int ?? 0
```

### Variables

Placeholders are written `$key`. A placeholder holding **text** goes inside a quoted literal; one holding a **number or boolean** is written bare:

```swift
let duplicateItem = AppleScriptBridge.AppleScriptObject(
    name: "duplicateItem",
    returnType: .bool,
    script: """
        tell application id "com.apple.finder"
            duplicate POSIX file "$source" to POSIX file "$destination" replacing $overwrite
            return true
        end tell
    """
)

let success = try AppleScriptBridge.executeAppleScript(duplicateItem, with: [
    "source": sourceURL.path(percentEncoded: false),
    "destination": destinationURL.path(percentEncoded: false),
    "overwrite": true
]) as? Bool ?? false
```

Variables may be supplied when the object is declared (`variables:`) or at call time (`with:`); runtime values win on conflict. Keys are substituted longest-first, so `$page` never eats the start of `$pageNumber`.

### Escaping, and how to opt out

Every `String` value is escaped on substitution. When a value is *meant* to be AppleScript source — a record list you built yourself, for example — wrap it in `AppleScriptRawValue` to insert it verbatim:

```swift
"filesArray": AppleScriptBridge.AppleScriptRawValue(records)  // inserted as code
"filePath":   url.path(percentEncoded: false)                 // inserted as escaped data
```

> **Warning:** never wrap unvalidated input in `AppleScriptRawValue`. Anything wrapped there is executed as code. Use `String.appleScriptStringEscaped` on each field when assembling raw source by hand.

### Return types

| `returnType` | Swift result |
|---|---|
| `.int` | `Int` |
| `.string` | `String` |
| `.bool` | `Bool` (non-zero is `true`) |
| `.list` | `[String]` |
| `.record` | `[String: Any]` — flat records only |
| `.json` | `[String: Any]` — for nested structures; build the JSON inside the script |
| `.none` | `nil` |

`.record` handles a flat `{name:"John", age:42}` and correctly leaves colons and commas that appear *inside* quoted values alone. For anything nested, build a JSON string in AppleScript and use `.json`.

### Threading

`NSAppleScript` is not thread-safe. `executeAppleScript(_:)` marshals calls arriving off the main thread onto the main queue and waits, so a background loop driving another application stays correct. The main thread is blocked for the duration of each individual script but is free between them, so progress UI keeps updating.

### Logging

The package logs prepared script sources through a closure you control. It prints in `DEBUG` builds by default:

```swift
AppleScriptBridge.logHandler = { message, details in myLogger.debug("\(message) \(details)") }
AppleScriptBridge.logHandler = nil   // silence
```

### Command-line execution

`executeAppleScriptViaCommandLine(_:)` runs the same script through `/usr/bin/osascript` instead, which sidesteps some `NSAppleScript` quirks. It spawns a subprocess, so it does not work inside the App Sandbox.

## ⚠️ Distribution: read this before you adopt the package

Controlling other applications through Apple events carries hard distribution consequences. They come from the platform, not from this package, and no amount of code can work around them.

**The Mac App Store is out.** Every App Store app must be sandboxed, and a sandboxed app cannot do what this package exists to do. Do not plan a Mac App Store release around it.

**Sandboxing is not viable.** The App Sandbox blocks Apple events outright unless the app carries `com.apple.security.automation.apple-events`, and that entitlement authorizes automation per target application, which a general-purpose bridge cannot enumerate ahead of time. On top of that, two facilities here — `executeAppleScriptViaCommandLine(_:)` and `resetAutomationPermission(for:)` — spawn subprocesses, which the sandbox forbids outright. Plan on shipping unsandboxed.

**Direct distribution is fully supported.** An unsandboxed app using this package can be signed with a Developer ID certificate, notarized by Apple, and stapled, exactly like any other app distributed outside the store. Users get no Gatekeeper warning. Distributing your own DMG, ZIP, or installer — or through Homebrew, Sparkle, or your own updater — works normally.

In short: **Developer ID + notarization, yes. Sandbox and Mac App Store, no.**

## Permissions the host app must provide

The package cannot declare these — your application must:

- **Entitlement** `com.apple.security.automation.apple-events`. Required for a sandboxed app, and also for a hardened-runtime app, which every notarized app is.
- **Info.plist** key `NSAppleEventsUsageDescription`, explaining why the app controls other applications. Without it, macOS terminates the app instead of prompting the user.

The first Apple event to a given target application raises the system Automation prompt. The user's answer is remembered per target, in System Settings ▸ Privacy & Security ▸ Automation.

Two helpers assist with the permission dance, both of which spawn subprocesses or Apple events and are therefore best used from a non-sandboxed build:

```swift
AppleScriptBridge.requestAutomationPermission(for: "com.apple.finder")  // triggers the system prompt
AppleScriptBridge.resetAutomationPermission()                          // tccutil reset, for testing
```

## Localization

The package's own messages are English only, by design. Applications that show errors to users in another language should switch over the `AppleScriptError` case and supply their own text rather than display `description` directly.

## Versioning

Semantic versioning. `1.x` ships in Swift 5 language mode: `AppleScriptObject` carries `[String: Any]`, which is not `Sendable`, and the API is synchronous. A future `2.0` is planned to adopt Swift 6 strict concurrency with a typed, `Sendable` variable representation.

## License

MIT. See [LICENSE](LICENSE).
