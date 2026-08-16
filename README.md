# SwiftAppleScriptBridge

A small, typed bridge between Swift and AppleScript for macOS applications.

## History

I had a personal need for a bridge like this, for apps that need to drive other apps — mostly Adobe InDesign. I couldn't find anything that did what I wanted, so I built my own. It works really well so I thought why not share it and hopefully improve it with contributions?

Don't get me wrong, AppleScriptObjC is a really good framework, but I wanted direct interaction between Swift and AppleScript, no middleman, plus easy conversion of booleans, strings, records, lists and integers between the two.

## What it does

It wraps `NSAppleScript` with three things that are tedious to get right by hand:

1. **Templated scripts.** Write AppleScript once with `$key` placeholders and fill them at call time.
1. **Automatic escaping.** Every substituted `String` is escaped before it reaches the script, so a folder named `Client "A"\B` cannot terminate a string literal and inject AppleScript.
1. **Typed results.** Declare what a script returns — `Int`, `String`, `Bool`, a list, a flat record, or JSON — and get a parsed Swift value back.

## How to use it

The best way to get speed out of this bridge is to do all the logic you can in Swift, and use the package only to fire off one task at a time at the app you're controlling. In other words, don't ask AppleScript to build lists or do calculations — only to tell the other app to do the things that only AppleScript can do.

The gains over a pure AppleScript solution are significant, and doing the heavy lifting in Swift is the main reason. You get the whole Swift platform, plus the small things: write a `///` comment above each `AppleScriptObject` and it shows up in Quick Help wherever you call it, and you get autocompletion.

You can scatter your scripts across the classes that use them, of course, but my suggestion is to put them all in one file — `AppleScripts.swift`, say — one `AppleScriptObject` each, documented, and call them from wherever you need. Everything is in one place, which makes them easier to find and maintain.

## How to contribute

See [CONTRIBUTING.md](CONTRIBUTING.md).

## Distribution: read this before you adopt the package

> [!IMPORTANT]
> **TL;DR:** an app using this package can't be sandboxed, and so can't go on the Mac App Store. Controlling other apps is what this package is for, and that's fundamentally at odds with the sandbox — which the App Store requires.
> 
> Developer ID signing and notarization work normally. See [Distribution](distribution-read-this-before-you-adopt-the-package).

Controlling other applications through Apple events carries hard distribution consequences. They come from the platform, not from this package, and no amount of code can work around them.

1. **The Mac App Store is out.** Every App Store app must be sandboxed, and a sandboxed app cannot do what this package exists to do. Do not plan a Mac App Store release around it.
1. **Sandboxing is not viable.** The App Sandbox blocks Apple events outright unless the app carries `com.apple.security.automation.apple-events`, and that entitlement authorizes automation per target application, which a general-purpose bridge cannot enumerate ahead of time. On top of that, two facilities here — `executeAppleScriptViaCommandLine(_:)` and `resetAutomationPermission(for:)` — spawn subprocesses, which the sandbox forbids outright. Plan on shipping unsandboxed.
1. **Direct distribution is fully supported.** An unsandboxed app using this package can be signed with a Developer ID certificate, notarized by Apple, and stapled, exactly like any other app distributed outside the store. Users get no Gatekeeper warning. Distributing your own DMG, ZIP, or installer — or through Homebrew, Sparkle, or your own updater — works normally.

## Installation

> [!WARNING]
> Requires macOS 13 or later. No dependencies.

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

### Variables and types

Placeholders are written `$key`. Variables may be supplied when the object is declared (`variables:`) or at call time (`with:`); runtime values win on conflict.

Substitution is textual: `preparedScript(with:)` replaces each `$key` with rendered text, then AppleScript compiles the result. So the type a script receives is decided by **how you wrote the placeholder**, not by the Swift type alone. A placeholder inside quotes — `"$key"` — always yields AppleScript **text**. A bare placeholder — `$key` — yields whatever literal the value rendered to.

> [!NOTE]
> Keys are substituted longest-first, so `$page` never eats the front of `$pageNumber`.

Strings are escaped on the way in (backslashes and double quotes), which is why they must be quoted: a bare `$name` holding `hello` would compile as an undefined identifier. Numbers and booleans render as bare literals, so a bare `$count` arrives as a real integer with nothing left to do. Quote one of those and it becomes text, and you have to coerce it at the top of the script: `set pageNumber to pageNumber as integer`. Wrapping a value in `AppleScriptRawValue` skips escaping entirely and inserts it as source, which is how you pass lists and records.

> [!NOTE]
> Pass POSIX paths as text and wrap them in the script (`POSIX file "$path"`), rather than converting to HFS form in Swift.

| Swift value | Rendered as | Write it as | AppleScript receives | Coercion in AppleScript |
|---|---|---|---|---|
| `String` | escaped text | `"$key"` | `text` | — |
| `String` | escaped text | `$key` | ⚠️ identifier — compile error | Do not use |
| `Int` | `42` | `$key` | `integer` | — |
| `Int` | `42` | `"$key"` | `text` | `as integer` |
| `Double` | `1.5` | `$key` | `real` | — |
| `Double` | `1.5` | `"$key"` | `text` | `as real` |
| `Bool` | `true` / `false` | `$key` | `boolean` | — |
| `Bool` | `true` / `false` | `"$key"` | `text` | `as boolean` |
| `AppleScriptRawValue` | verbatim source | `$key` | whatever it evaluates to | — |
| object references | ⚠️ Not available. See warning below | — | — | — |
| anything else | escaped `String(describing:)` | `"$key"` | `text` | parse manually |

```swift
let script = AppleScriptBridge.AppleScriptObject(
    name: "example",
    returnType: .bool,
    script: """
        tell application id "com.apple.finder"
            set thePath to "$path"        -- text, escaped for you
            set theCount to $count        -- integer, no coercion
            set theFlag to $flag          -- boolean, no coercion

            ... rest of your code here...

            return theFlag
        end tell
    """
)

try AppleScriptBridge.executeAppleScript(script, with: [
    "path": url.path(percentEncoded: false),
    "count": 3,
    "flag": true
])
```

> [!IMPORTANT]
> Application-specific object references can't come back to Swift. Only the types in the table above survive the trip.
>
> ```applescript
> tell application id "com.adobe.InDesign" to set newPage to make new page
> ```
>
> `newPage` is a live reference to an object inside InDesign, not data. There's no Swift equivalent, and asking for it as `.string` gets you whatever the app's coercion happens to produce — usually something unusable, sometimes an error. The same goes for aliases, file specifiers, dates, and anything else the app defines.
>
> Keep those references inside AppleScript. If you need to identify the object later, return something addressable instead — its id, name, or index — and use that to look it up on the next call:
>
> ```applescript
> tell application id "com.adobe.InDesign"
>     set newPage to make new page
>     return id of newPage
> end tell
> ```

### Escaping, and how to opt out

Every `String` value is escaped on substitution. That's what you want almost all of the time — a path or a filename should arrive as *data*, not as code.

But sometimes the thing you're substituting really is AppleScript source. There's no automatic conversion for a Swift array, for instance, so if you want AppleScript to receive a list you have to write that list out yourself and tell the bridge not to escape it. That's what `AppleScriptRawValue` is for:

```swift
"filesArray": AppleScriptBridge.AppleScriptRawValue(records)  // inserted as code
"filePath":   url.path(percentEncoded: false)                 // inserted as escaped data
```

#### A worked example

Say you want to hand AppleScript a list of file paths. You build the list in Swift:

```swift
let paths = urls.map { "\"\($0.path(percentEncoded: false).appleScriptStringEscaped)\"" }
let list = "{" + paths.joined(separator: ", ") + "}"

let script = AppleScriptBridge.AppleScriptObject(
    name: "processFiles",
    returnType: .int,
    script: """
        set theFiles to $files
        repeat with aPath in theFiles
            -- do something with aPath
        end repeat
        return count of theFiles
    """
)

try AppleScriptBridge.executeAppleScript(script, with: [
    "files": AppleScriptBridge.AppleScriptRawValue(list)
])
```

Note the `.appleScriptStringEscaped` on each path, and the placeholder written bare as `$files` rather than `"$files"`. You skipped the bridge's escaping by using `AppleScriptRawValue`, so escaping each individual value is now your job.

#### What happens if you forget

Filenames can contain quotes. Take a file actually named `My "best" shot.jpg`. Without escaping, your generated list is:

```applescript
{"/Photos/My "best" shot.jpg"}
```

AppleScript reads that as the string `/Photos/My `, followed by a stray `best`, and the script fails to compile. That's the harmless outcome. A filename crafted on purpose can close the string and append its own commands, which then run with your app's automation permissions — that's the reason the escaping exists.

With `.appleScriptStringEscaped` applied, the same file comes out as valid, inert text:

```applescript
{"/Photos/My \"best\" shot.jpg"}
```

> [!WARNING]
> Never wrap unvalidated input in `AppleScriptRawValue` — anything wrapped there is executed as code. Only use it for source you generated yourself, and escape every value you interpolate into that source with `String.appleScriptStringEscaped`.

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

### Choosing an execution method

Both methods take the same `AppleScriptObject` and the same optional runtime variables, and both interpret the result according to the script's `returnType`. They differ in how the script actually runs.

| | `executeAppleScript(_:with:)` | `executeAppleScriptViaCommandLine(_:with:)` |
|---|---|---|
| Engine | `NSAppleScript`, in-process | `/usr/bin/osascript` in a subprocess |
| **Use it when** | Always, unless you have a specific reason not to | You hit an `NSAppleScript` quirk, or want the script isolated from your process |
| Threading | Calls off the main thread are marshalled onto the main queue and awaited, since `NSAppleScript` is not thread-safe | No marshalling needed — the work happens in another process |
| Blocks the main thread | Yes, for the duration of each script. See [Threading](#threading) | No |
| Overhead | Compiles in-process; no process launch | Launches a process per call |
| Script errors | Thrown as `AppleScriptError.executionError` | ⚠️ Not detected — see below |
| Crash/hang isolation | A hung script hangs your main thread | Contained in the subprocess |
| `.list` separator | Splits on newlines | Splits on `\r` |
| Logging | Logs the compiled source | Logs the object description, including variable values |

The error handling gap is the reason to prefer the first method. `executeAppleScriptViaCommandLine` pipes `stderr` into the same pipe as `stdout` and ignores the exit status, so a script that fails returns osascript's error text as if it were a successful result — a `.string` call yields the error message, and an `.int` call yields `nil` from a failed `Int(...)` conversion. Only a launch failure throws. If you use this method, validate what comes back.

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

### Threading

`NSAppleScript` is not thread-safe. `executeAppleScript(_:)` marshals calls arriving off the main thread onto the main queue and waits, so a background loop driving another application stays correct. The main thread is blocked for the duration of each individual script but is free between them, so progress UI keeps updating.

### Logging

The package logs prepared script sources through a closure you control. It prints in `DEBUG` builds by default:

```swift
AppleScriptBridge.logHandler = { message, details in myLogger.debug("\(message) \(details)") }
AppleScriptBridge.logHandler = nil   // silence
```

## Localization

The package's own messages are English only, by design. Applications that show errors to users in another language should switch over the `AppleScriptError` case and supply their own text rather than display `description` directly.

## Versioning

Semantic versioning. `1.x` ships in Swift 5 language mode: `AppleScriptObject` carries `[String: Any]`, which is not `Sendable`, and the API is synchronous. A future `2.0` is planned to adopt Swift 6 strict concurrency with a typed, `Sendable` variable representation.

## License

MIT. See [LICENSE](LICENSE).
