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

## Distribution: read this if you intend to distribute/notarize/sign your app

> [!IMPORTANT]
> **TL;DR:** an app using this package can't be sandboxed, therefore cannot go on the Mac App Store. Controlling other apps is what this package is for, and that's fundamentally at odds with the sandbox — which the App Store requires. Controlling other applications through [Apple Events](https://en.wikipedia.org/wiki/Apple_event) carries hard distribution consequences. They come from the platform, not from this package, and no amount of code can work around them.
> 
> [**Developer ID signing**](https://developer.apple.com/developer-id/) and [**notarization**](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) work like for any other macOS apps.

### In details...
1. **The Mac App Store is out.** Every App Store app must be sandboxed, and a sandboxed app cannot do what this package exists to do. Do not plan a Mac App Store release around it.
1. **Sandboxing is not viable.** The App Sandbox blocks Apple events outright unless the app carries `com.apple.security.automation.apple-events`, and that entitlement authorizes automation per target application, which a general-purpose bridge cannot enumerate ahead of time. On top of that, two facilities here — `executeAppleScriptViaCommandLine(_:)` and `resetAutomationPermission(for:)` — spawn subprocesses, which the sandbox forbids outright. Plan on shipping unsandboxed.
1. **Direct distribution is fully supported.** An unsandboxed app using this package can be signed with a Developer ID certificate, notarized by Apple, and stapled, exactly like any other app distributed outside the store. Users get no Gatekeeper warning. Distributing your own DMG, ZIP, or installer — or through Homebrew, Sparkle, or your own updater — works normally.

## Installation

> [!WARNING]
> Requires macOS 13 or later (tested on macOS 15 and 26 only). No dependencies.

A. In Xcode: **File ▸ Add Package Dependencies…**, then paste the repository URL:

```
https://github.com/fredsimard/SwiftAppleScriptBridge
```

B. Or in a `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/fredsimard/SwiftAppleScriptBridge", from: "1.1.0")
]
```

## Usage

> [!NOTE]
> Although the form `tell application id` + `bundle identifier` is used in this repo nothing prevents you from using the classic `tell application "App name"`. I personally prefer the former as it is more flexible with newer versions of applications like InDesign which change their app's name in AppleScript every time they release a major version.

### Full API documentation
See the full API reference here: [Documentation/API.md](Documentation/API.md).

### `AppleScript.swift` example
Complete example of the one-file-of-scripts layout here: [Examples/AppleScripts.swift](Examples/AppleScripts.swift) (with a script for every return type and the call site that goes with it).

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


### If your project uses Swift 6 language mode

`AppleScriptObject` holds a `[String: Any]` of variables, so it can't be `Sendable`, and Swift 6 rejects a `static let` of a non-`Sendable` type. Declaring your scripts as static constants — which is what I'd recommend, and what the example file does — therefore fails to compile with a message like *"static property 'countOpenWindows' is not concurrency-safe"*.

Mark them `nonisolated(unsafe)` and it compiles in both language modes:

```swift
nonisolated(unsafe) static let countOpenWindows = AppleScriptBridge.AppleScriptObject(
```

It reads worse than it behaves: these are immutable value types built once and never written to, so the unsafety is theoretical. Projects on Swift 5 mode need none of this. Getting rid of the keyword entirely is tracked in [#2](https://github.com/fredsimard/SwiftAppleScriptBridge/issues/2).

### Variables and types

Placeholders are written `$key`. Variables may be supplied when the object is declared (`variables:`) or at call time (`with:`); runtime values win on conflict.

Substitution is textual: `preparedScript(with:)` replaces each `$key` with rendered text, then AppleScript compiles the result. So the type a script receives is decided by **how you wrote the placeholder**, not by the Swift type alone. 

A placeholder inside quotes — i.e. `"$key"` — always yields AppleScript **text**, whatever the Swift value was, so a number or a boolean written that way needs coercing in the script (`"$key" as integer`). A bare placeholder — `$key` — yields the literal the value rendered to, already typed and needing nothing further.

> [!NOTE]
> Keys are substituted longest-first, so `$page` never eats the front of `$pageNumber`.

Strings are escaped on the way in (backslashes and double quotes), which is why they must be quoted: a bare `$name` holding `hello` would compile as an undefined identifier. Numbers, booleans and collections render as bare literals, so a bare `$count` arrives as a real integer with nothing left to do. Quote one of those and it becomes text, and you have to coerce it at the top of the script: `set pageNumber to pageNumber as integer`. Wrapping a value in `AppleScriptRawValue` skips escaping entirely and inserts it as source, which is the escape hatch for script fragments no type mapping covers.

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
| `Array` | `{"a", "b"}` | `$key` | `list` | — |
| `Dictionary` | `{name:"Roger", age:42}` | `$key` | `record` | — |
| `AppleScriptRawValue` | verbatim source | `$key` | whatever it evaluates to | — |
| HFS path (a `String`, from `toHFSPath()`) | escaped text | `"$path"` | `text` | `as alias`, or `as «class furl»` |
| POSIX path (a `String`) | escaped text | `POSIX file "$path"` | `file` specifier | — or `as alias` if the app wants one |
| object references | ⚠️ Not available. See warning below this table. | — | — | — |
| anything else | escaped `String(describing:)` | `"$key"` | `text` | parse manually |

> [!IMPORTANT]
> Application-specific object references can't come back to Swift. Only the types in the table above survive the trip. For example:
>
> ```applescript
> tell application id "com.adobe.InDesign" to set newPage to make new page
> ```
>
> ... will not work as the `newPage` var is a live reference to an object inside InDesign, not data. There's no Swift equivalent, and asking for it as `.string` gets you whatever the app's coercion happens to produce — usually something unusable, sometimes an error. The same goes for aliases, file specifiers, dates, and anything else the app defines.
>
> Keep those references inside AppleScript. If you need to identify the object later, return something addressable instead — its id, name, or index — and use that to look it up on the next call:
>
> ```applescript
> tell application id "com.adobe.InDesign"
>     set newPage to make new page
>     return id of newPage
> end tell
> ```

#### Example

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

#### Lists and records

Arrays become AppleScript lists and dictionaries become records, with every element escaped on the way in. They nest, so an array of dictionaries arrives as a list of records — the shape most scripts actually want:

```swift
let script = AppleScriptBridge.AppleScriptObject(
    name: "tagFiles",
    variables: ["items": [["path": "/tmp/a.txt", "tags": ["draft", "q3"]],
                          ["path": "/tmp/b.txt", "tags": [] as [String]]]],
    script: """
        repeat with anItem in $items
            set thePath to path of anItem   -- text
            set theTags to tags of anItem   -- list
        end repeat
    """
)
```

The placeholder is written bare — `$items`, not `"$items"` — since it renders as a literal, not as text.

Record keys are AppleScript identifiers, not strings, so a key that isn't a plain identifier (`first name`, `2nd`) or that is one of AppleScript's reserved words (`set`, `end`, `to`) is written vertical-bar quoted: `{|first name|:"Roger"}`. Read it back out of the record the same way, with the bars. Keys that *are* plain identifiers are left bare, so a term the target application defines keeps its meaning. Dictionary keys are sorted when rendered, so the same dictionary always produces the same script source.

Two things to know. AppleScript writes an empty list and an empty record identically, as `{}`, so an empty dictionary renders as `{}` and the script decides what it is. And a dictionary key that isn't a `String` is described first, which is what a dictionary bridged from Objective-C or from `JSONSerialization` needs.

### Return types

| `returnType` | Swift result |
|---|---|
| `.int` | `Int` |
| `.string` | `String` |
| `.bool` | `Bool` (the script's `true`/`false`, or any non-zero number) |
| `.list` | `[String]` |
| `.record` | `[String: Any]` — flat records only |
| `.json` | `[String: Any]` — for nested structures; build the JSON inside the script |
| `.wildCard` | `AppleScriptValue` — whatever the script returned, with its actual type |
| `.none` | `nil` |

`.record` handles a flat `{name:"John", age:42}` and correctly leaves colons and commas that appear *inside* quoted values alone. For anything nested, build a JSON string in AppleScript and use `.json`.

#### When the type is the answer

Every return type above coerces: you declare one, and whatever comes back is read as that. Some application properties don't work that way — they answer with a *different type* depending on state. The `value` of a cell in Numbers is documented as "number, date, text, boolean, or `missing value`", the last one meaning the cell is empty. Declare `.int` there and an empty cell is indistinguishable from a cell holding zero.

`.wildCard` skips the coercion. The result comes back as an `AppleScriptValue` built from what the Apple event actually carried, so you switch on the type instead of assuming it:

```swift
let script = AppleScriptBridge.AppleScriptObject(
    name: "cellValue",
    returnType: .wildCard,
    script: """
        tell application "Numbers" to tell document 1 to tell sheet 1
            return value of cell "$cell" of table 1
        end tell
    """
)

switch try AppleScriptBridge.executeAppleScript(script, with: ["cell": "B2"]) as? AppleScriptBridge.AppleScriptValue {
    case .double(let number): print("number: \(number)")
    case .string(let text):   print("text: \(text)")
    case .date(let date):     print("date: \(date)")
    case .bool(let flag):     print("boolean: \(flag)")
    case .missingValue:       print("the cell is empty")
    default:                  break
}
```

| `AppleScriptValue` case | What it carries |
|---|---|
| `.double` / `.int` / `.string` / `.bool` | The scalar, as its own type |
| `.date` | `Date` |
| `.fileURL` | `URL`, for an alias or a file URL |
| `.missingValue` | AppleScript's `missing value` |
| `.constant` | An application-defined constant, as its raw `FourCharCode` |
| `.list` / `.record` | `[AppleScriptValue]` / `[String: AppleScriptValue]`, decoded recursively |
| `.unknown` | The `NSAppleEventDescriptor` itself, for anything not decoded above |

A few things to know:

- **Constants come as raw codes.** There is no general mapping from a four-character code to a meaning — what `'autp'` means is defined by the application's dictionary, not by AppleScript. Compare against the codes your target documents: `if case .constant("autp".appleScriptFourCharCode) = value`. `missing value` is the one exception, and gets a case of its own.
- **Record keys are as written, or as compiled.** A key you wrote yourself comes through by name, but a key AppleScript recognizes as its own terminology is compiled to a four-character code before the script runs. `{name:"Roger", age:42}` decodes as `["pnam": .string("Roger"), "age": .int(42)]`.
- **`NSAppleScript` only.** `executeAppleScriptViaCommandLine` throws `.unsupportedReturnType` on a `.wildCard` script, without running it. `osascript` prints its result as text, so the type is already gone by the time that method could read anything.

### Escaping, and how to opt out

Every `String` value is escaped on substitution. That's what you want almost all of the time — a path or a filename should arrive as *data*, not as code.

But sometimes the thing you're substituting really is AppleScript source — an expression, a call, a fragment that no type mapping covers. Wrapping it in `AppleScriptRawValue` tells the bridge to insert it unchanged instead of escaping it:

```swift
"filesArray": AppleScriptBridge.AppleScriptRawValue(records)  // inserted as code
"filePath":   url.path(percentEncoded: false)                 // inserted as escaped data
```

#### Example

Say you want to hand AppleScript a list of file paths, and you build the list yourself:

> [!NOTE]
> You no longer have to: passing the `[String]` straight through renders the same list, escaped for you. The example is kept because it shows what building source by hand involves, and what the escaping is protecting you from.

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

> [!NOTE]
> Note the `.appleScriptStringEscaped` on each path, and the placeholder written bare as `$files` rather than `"$files"`. You skipped the bridge's escaping by using `AppleScriptRawValue`, so escaping each individual value is now your job.
> 
> **What happens if you forget**
> 
> Filenames can contain quotes. Take a file actually named `My "best" shot.jpg`. Without escaping, your generated list is:
> 
> ```applescript
> {"/Photos/My "best" shot.jpg"}
> ```
> 
> AppleScript reads that as the string `/Photos/My `, followed by a stray `best`, and the script fails to compile. That's the harmless outcome. A filename crafted on purpose can close the string and append its own commands, which then run with your app's automation permissions — that's the reason the escaping exists.
> 
> With `.appleScriptStringEscaped` applied, the same file comes out as valid, inert text:
> 
> ```applescript
> {"/Photos/My \"best\" shot.jpg"}
> ```

> [!WARNING]
> Never wrap unvalidated input in `AppleScriptRawValue` — anything wrapped there is executed as code. Only use it for source you generated yourself, and escape every value you interpolate into that source with `String.appleScriptStringEscaped`.

## Choosing an execution method

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

## Threading

`NSAppleScript` is not thread-safe. `executeAppleScript(_:)` marshals calls arriving off the main thread onto the main queue and waits, so a background loop driving another application stays correct. The main thread is blocked for the duration of each individual script but is free between them, so progress UI keeps updating.

## Logging

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
