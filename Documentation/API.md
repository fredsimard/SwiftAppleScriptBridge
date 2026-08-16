# API reference

Every public type, method and property in the package, grouped by the file it lives in. Anything not listed here is internal and not part of the API contract.

- [AppleScriptBridge](#applescriptbridge) — executing scripts, logging, permissions
- [AppleScriptObject](#applescriptobject) — the script model, return types, raw values
- [AppleScriptError](#applescripterror) — error cases
- [String and URL extensions](#string-and-url-extensions) — escaping, paths, result parsing

---

## AppleScriptBridge

`Sources/SwiftAppleScriptBridge/AppleScriptBridge.swift`

```swift
public class AppleScriptBridge: NSObject
```

The entry point. Everything on it is `static`, so you never instantiate it. It compiles and runs `AppleScriptObject` scripts, escapes substituted values, and parses results into the Swift type each script declares.

### `logHandler`

```swift
public static var logHandler: ((_ message: String, _ details: String) -> Void)?
```

The closure invoked to log compiled script sources and diagnostics. Defaults to printing in `DEBUG` builds only.

| Closure parameter | Meaning |
|---|---|
| `message` | A short label describing what is being logged. |
| `details` | The script source or other multi-line detail, possibly empty. |

Assign your own closure to route logging into your app, or assign `nil` to silence the package entirely.

```swift
AppleScriptBridge.logHandler = { message, details in logger.debug("\(message) \(details)") }
AppleScriptBridge.logHandler = nil
```

> [!NOTE]
> `executeAppleScript(_:with:)` logs the compiled source, while `executeAppleScriptViaCommandLine(_:with:)` logs the object description, which includes variable values. Bear that in mind if your variables carry anything sensitive.

### `executeAppleScript(_:with:)`

```swift
public static func executeAppleScript(
    _ AppleScript: AppleScriptObject,
    with runtimeVariables: [String: Any]? = nil
) throws -> Any?
```

Compiles and runs a script with `NSAppleScript`, and interprets the result according to the script's `returnType`. This is the method you want in almost every case.

| Parameter | Description |
|---|---|
| `AppleScript` | The script object to execute. |
| `runtimeVariables` | Variables resolved at call time, overriding the object's predefined ones of the same name. Defaults to `nil`. |

**Returns** the script's result cast to the declared type — `Int`, `String`, `Bool`, `[String]`, `[String: Any]`, or `nil` for `.none`.

**Throws**

| Error | When |
|---|---|
| `AppleScriptError.failedToInitScript` | The source could not be compiled. |
| `AppleScriptError.executionError` | The script ran but returned an error. |

> [!NOTE]
> A script returning `0` yields `0`, not `nil`. Failure is reported by throwing, so you can tell "the target app answered zero" from "the target app did not answer".

> [!NOTE]
> `NSAppleScript` is not thread-safe, so calls arriving off the main thread are marshalled onto the main queue and awaited. The main thread is blocked for the duration of each individual script, but is free between them, so progress UI keeps updating.

### `executeAppleScriptViaCommandLine(_:with:)`

```swift
public static func executeAppleScriptViaCommandLine(
    _ AppleScript: AppleScriptObject,
    with runtimeVariables: [String: Any]? = nil
) throws -> Any?
```

Runs the same script through `/usr/bin/osascript` in a subprocess instead. Useful if you hit an `NSAppleScript` quirk, or want a long script isolated from your process. Parameters and return values match `executeAppleScript(_:with:)`, with two differences: `.list` splits on `\r` rather than on newlines, and only a launch failure throws.

**Throws**

| Error | When |
|---|---|
| `AppleScriptError.executionError` | The process failed to launch. |
| `AppleScriptError.failedToReadOutput` | The output was not valid UTF-8. |

> [!WARNING]
> Script errors are **not** detected. `stderr` is piped into the same pipe as `stdout` and the exit status is ignored, so a failing script returns osascript's error text as if it were a result — a `.string` call yields the error message, an `.int` call yields `nil`. Validate what comes back if you use this method.

### `requestAutomationPermission(for:activating:)`

```swift
@discardableResult
public static func requestAutomationPermission(
    for bundleIdentifier: String,
    activating: Bool = true
) -> Bool
```

Sends a harmless Apple event to an application to force macOS to show the Automation permission prompt. The script asks the target to close the startup disk, which it cannot do; the attempt is enough to trigger the prompt, and the resulting error is swallowed inside the script.

| Parameter | Description |
|---|---|
| `bundleIdentifier` | The application to request permission for, for example `"com.apple.finder"`. |
| `activating` | Whether the target is brought to the foreground, which also launches it if it isn't running. Defaults to `true`. |

**Returns** `true` if the probe ran without error. Errors are logged through `logHandler` and do not otherwise affect app flow.

### `resetAutomationPermission(for:)`

```swift
@discardableResult
public static func resetAutomationPermission(
    for bundleIdentifier: String? = Bundle.main.bundleIdentifier
) -> Bool
```

Clears an application's Apple Events authorization by running `tccutil`. macOS will prompt again the next time automation is attempted. Mainly useful for testing the first-run experience.

| Parameter | Description |
|---|---|
| `bundleIdentifier` | Whose authorization to reset. Defaults to your own app. If `nil`, the reset is skipped rather than run without a target, so other applications' authorizations are never affected. |

**Returns** `true` if `tccutil` ran to completion, `false` if the identifier was missing or the process failed to launch.

---

## AppleScriptObject

`Sources/SwiftAppleScriptBridge/AppleScriptObject.swift`

### `AppleScriptReturnType`

```swift
public enum AppleScriptReturnType: Sendable
```

How a script's result should be interpreted.

| Case | Swift result |
|---|---|
| `.int` | `Int` |
| `.string` | `String` |
| `.bool` | `Bool` — non-zero is `true` |
| `.list` | `[String]` |
| `.record` | `[String: Any]` — flat records only |
| `.json` | `[String: Any]` — for nested structures; build the JSON inside the script |
| `.none` | `nil` |

### `AppleScriptRawValue`

```swift
public struct AppleScriptRawValue: Sendable {
    public let source: String
    public init(_ source: String)
}
```

Wraps a value that is already valid AppleScript source, so it is substituted verbatim instead of being escaped. Use it for lists and records you generated yourself.

> [!WARNING]
> Never wrap unvalidated input in this type — anything wrapped here is inserted unchanged and executed as code. Escape every value you interpolate into that source with `appleScriptStringEscaped`.

### `AppleScriptObject`

```swift
public struct AppleScriptObject {
    public let name: String
    public let returnType: AppleScriptReturnType
    public let variables: [String: Any]?
    public let script: String
}
```

A script, its expected return type, and the variables filling its placeholders.

| Property | Description |
|---|---|
| `name` | A unique name identifying the script, used for logging and display. |
| `returnType` | How the result should be interpreted. |
| `variables` | Predefined variables substituted into `$key` placeholders. |
| `script` | The raw AppleScript source, with optional `$key` placeholders. |

#### `init(name:returnType:variables:script:)`

```swift
public init(
    name: String,
    returnType: AppleScriptReturnType = .none,
    variables: [String: Any]? = nil,
    script: String
)
```

Only `name` and `script` are required.

#### `preparedScript(with:)`

```swift
public func preparedScript(with runtimeVariables: [String: Any]? = nil) -> String
```

Returns the source with every `$key` placeholder replaced by its value, ready to compile. Predefined `variables` are merged with `runtimeVariables`, the latter winning on conflict. Both execution methods call this for you; call it directly to inspect or debug what will actually run.

Values are rendered like this:

| Swift value | Rendered as |
|---|---|
| `AppleScriptRawValue` | its `source`, verbatim |
| `String` | escaped text, for use inside `"..."` |
| `Bool` | `true` / `false` |
| `Int`, `Double` | the bare number |
| anything else | escaped `String(describing:)`, so an unforeseen type fails safe |

> [!NOTE]
> Keys are substituted longest-first, so `$page` never eats the front of `$pageNumber`.

#### `description()`

```swift
public func description() -> String
```

A human-readable, multi-line dump of the script's name, return type, variables and source. For logging and debugging.

---

## AppleScriptError

`Sources/SwiftAppleScriptBridge/AppleScriptError.swift`

```swift
public enum AppleScriptError: Error {
    case failedToInitScript
    case failedToReadOutput
    case executionError(String)
    case genericMessage(String)
}
```

| Case | Meaning |
|---|---|
| `failedToInitScript` | The script could not be compiled. |
| `failedToReadOutput` | It ran, but the output could not be read. |
| `executionError(String)` | It ran and returned an error, carried as text. |
| `genericMessage(String)` | A catch-all with your own message, for your code to throw. |

### `description`

```swift
public var description: String
```

A human-readable explanation of the error.

> [!NOTE]
> These messages are English only. If you show errors to users in another language, switch over the case and supply your own text rather than displaying `description` directly.

---

## String and URL extensions

`Sources/SwiftAppleScriptBridge/StringExtensions.swift`

### `String.appleScriptStringEscaped`

```swift
public var appleScriptStringEscaped: String
```

A copy of the string safe to embed inside an AppleScript `"..."` literal. Escapes backslashes first, then double quotes — the only two characters that need it.

`preparedScript(with:)` applies this automatically to every `String` variable, so you only need it when assembling AppleScript source by hand for an `AppleScriptRawValue`.

### `String.parseSimpleAppleScriptRecord()`

```swift
public func parseSimpleAppleScriptRecord() -> [String: Any]?
```

Parses a flat AppleScript record such as `{name:"John Doe", age:42, active:true}` into a dictionary of `String`, `Int`, `Double` and `Bool` values. Returns `nil` if the text is not a flat record. Used automatically by the `.record` return type.

The record is scanned character by character rather than rewritten into JSON, so colons and commas *inside* quoted values — common in file paths and times — are correctly treated as content.

**Limitations:** keys must be alphanumeric, string values must be double-quoted, and nested records or lists are not supported. Use `.json` for anything nested.

### `String.parseJSONStringFromAppleScript()`

```swift
public func parseJSONStringFromAppleScript() -> [String: Any]?
```

Decodes a JSON object built inside AppleScript — by string concatenation, typically — into a dictionary. Returns `nil` if the text isn't valid JSON, or is valid JSON that isn't an object. Used automatically by the `.json` return type. This is the route for nested structures that `parseSimpleAppleScriptRecord()` can't handle.

### `String.toPOSIXPath()`

```swift
public func toPOSIXPath() -> String?
```

Converts an HFS-style path (`Macintosh HD:Users:roger:Desktop`) to POSIX (`/Users/roger/Desktop`). Returns `nil` if the conversion fails.

### `String.toHFSPath()` / `URL.toHFSPath()`

```swift
public func toHFSPath() -> String?
```

The reverse: POSIX to HFS-style. Returns `nil` if the startup disk name can't be read. The `URL` version delegates to the `String` one, so the two can't drift apart.

> [!NOTE]
> Most scriptable applications now expect POSIX paths, which are better passed as text and wrapped in the script with `POSIX file "$path"`. These conversions are here for the applications and script dialects that still want HFS paths.
