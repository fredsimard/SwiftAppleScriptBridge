# API reference

Every public type, method and property in the package, grouped by the file it lives in. Anything not listed here is internal and not part of the API contract.

- [AppleScriptBridge](#applescriptbridge) — executing scripts, logging, permissions
- [AppleScriptObject](#applescriptobject) — the script model, return types, raw values
- [AppleScriptValue](#applescriptvalue) — the uncoerced result of a `.wildCard` script
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

**Returns** the script's result cast to the declared type — `Int`, `String`, `Bool`, `[String]`, `[String: Any]`, [`AppleScriptValue`](#applescriptvalue) for `.wildCard`, or `nil` for `.none`.

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

Runs the same script through `/usr/bin/osascript` in a subprocess instead. Useful if you hit an `NSAppleScript` quirk, or want a long script isolated from your process. Parameters and return values match `executeAppleScript(_:with:)`, with three differences: `.list` splits on `\r` rather than on newlines, a failing script does not throw — only a launch failure or undecodable output does — and `.wildCard` is refused.

**Throws**

| Error | When |
|---|---|
| `AppleScriptError.executionError` | The process failed to launch. |
| `AppleScriptError.failedToReadOutput` | The output was not valid UTF-8. |
| `AppleScriptError.unsupportedReturnType` | The script declared `.wildCard`. Checked before the process is launched, so the script does not run. |

> [!WARNING]
> Script errors are **not** detected. `stderr` is piped into the same pipe as `stdout` and the exit status is ignored, so a failing script returns osascript's error text as if it were a result — a `.string` call yields the error message, an `.int` call yields `nil`. Validate what comes back if you use this method.

> [!WARNING]
> The fully substituted script is passed to `osascript` as a command-line argument, so any local process can read it with `ps`. If your variables carry sensitive strings, prefer `executeAppleScript(_:with:)`.

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
| `.bool` | `Bool` — the script's `true`/`false`, or any non-zero number |
| `.list` | `[String]` |
| `.record` | `[String: Any]` — flat records only |
| `.json` | `[String: Any]` — for nested structures; build the JSON inside the script |
| `.wildCard` | [`AppleScriptValue`](#applescriptvalue) — the result with its actual type, uncoerced |
| `.none` | `nil` |

`.wildCard` is the only case that does not coerce, and the only one `executeAppleScriptViaCommandLine(_:with:)` refuses.

### `AppleScriptRawValue`

```swift
public struct AppleScriptRawValue: Sendable {
    public let source: String
    public init(_ source: String)
}
```

Wraps a value that is already valid AppleScript source, so it is substituted verbatim instead of being escaped. Arrays and dictionaries are converted for you, so this is for the fragments no type mapping covers: an expression, a call, terminology you assembled yourself.

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
| `Array` | an AppleScript list, `{"a", "b"}`, each element rendered by these same rules |
| `Dictionary` | an AppleScript record, `{name:"Roger", age:42}`, keys sorted and quoted only where AppleScript needs it |
| anything else | escaped `String(describing:)`, so an unforeseen type fails safe |

Collections nest, so an array of dictionaries renders as a list of records. Both render as bare literals: write the placeholder as `$key`, not `"$key"`. A record key that is not a plain identifier, or that is one of AppleScript's reserved words, is vertical-bar quoted — `{|first name|:"Roger"}` — and has to be read back out of the record the same way. An empty dictionary renders as `{}`, which is also how AppleScript writes an empty list.

> [!NOTE]
> Keys are substituted longest-first, so `$page` never eats the front of `$pageNumber`.

#### `description()`

```swift
public func description() -> String
```

A human-readable, multi-line dump of the script's name, return type, variables and source. For logging and debugging.

---

## AppleScriptValue

`Sources/SwiftAppleScriptBridge/AppleScriptValue.swift`

```swift
public enum AppleScriptValue: Equatable {
    case double(Double)
    case int(Int)
    case string(String)
    case bool(Bool)
    case date(Date)
    case fileURL(URL)
    case missingValue
    case constant(FourCharCode)
    case list([AppleScriptValue])
    case record([String: AppleScriptValue])
    case unknown(NSAppleEventDescriptor)
}
```

What a `.wildCard` script returns. Built from the Apple event descriptor's own type, so nothing is coerced: a property that answers with a number most of the time and `missing value` otherwise can be told apart at the call site.

| Case | Descriptor types | Carries |
|---|---|---|
| `.double` | `'doub'`, `'sing'`, `'ldbl'` | `Double`. AppleScript answers with a real for any whole number its 32-bit integer cannot hold, and for overflow, which is `Double.infinity`. |
| `.int` | `'shor'`, `'ushr'`, `'long'`, `'magn'`, `'comp'`, `'ucom'` | `Int`, read at the descriptor's own width rather than coerced to 32 bits. |
| `.string` | `'utxt'`, `'utf8'`, `'ut16'`, `'TEXT'`, `'cstr'` | `String`. |
| `.bool` | `'bool'`, `'true'`, `'fals'` | `Bool`. |
| `.date` | `'ldt '` | `Date`. |
| `.fileURL` | `'furl'`, `'alis'`, `'bmrk'` | `URL`. |
| `.missingValue` | `'type'` carrying `'msng'` | Nothing — AppleScript's `missing value`. |
| `.constant` | `'enum'`, `'type'`, `'prop'`, `'keyw'` | `FourCharCode`, raw. |
| `.list` | `'list'` | `[AppleScriptValue]`, decoded recursively. |
| `.record` | `'reco'` | `[String: AppleScriptValue]`, decoded recursively. |
| `.unknown` | anything else | The `NSAppleEventDescriptor`, untouched. |

> [!NOTE]
> Record keys come through as the caller wrote them only when AppleScript did not recognize them as terminology. `{name:"Roger", age:42}` decodes as `["pnam": .string("Roger"), "age": .int(42)]`, because `name` compiles to the `'pnam'` property. Application-returned records are terminology throughout, so expect codes there.

> [!NOTE]
> A constant carries no meaning of its own: what `'autp'` means comes from the application's dictionary. Compare it against the codes your target documents.

### `init(descriptor:)`

```swift
public init(descriptor: NSAppleEventDescriptor)
```

Decodes a descriptor into a value, recursively. `executeAppleScript(_:with:)` calls this for a `.wildCard` script; call it yourself to decode a descriptor you got some other way, or one you coerced out of an `.unknown`.

A descriptor whose type is not decoded — or one that is, but whose value cannot be read, such as an unsigned 64-bit integer larger than `Int.max` — yields `.unknown` rather than a wrong value.

---

## AppleScriptError

`Sources/SwiftAppleScriptBridge/AppleScriptError.swift`

```swift
public enum AppleScriptError: Error {
    case failedToInitScript
    case failedToReadOutput
    case executionError(String)
    case unsupportedReturnType(AppleScriptReturnType)
    case genericMessage(String)
}
```

| Case | Meaning |
|---|---|
| `failedToInitScript` | The script could not be compiled. |
| `failedToReadOutput` | It ran, but the output could not be read. |
| `executionError(String)` | It ran and returned an error, carried as text. |
| `unsupportedReturnType(AppleScriptReturnType)` | The execution method cannot produce the declared type. Today that is `.wildCard` through `executeAppleScriptViaCommandLine(_:with:)`. |
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

**Limitations:** a key is everything up to the first colon and cannot be empty, string values must be double-quoted, and nested records or lists are not supported. Use `.json` for anything nested.

### `String.parseJSONStringFromAppleScript()`

```swift
public func parseJSONStringFromAppleScript() -> [String: Any]?
```

Decodes a JSON object built inside AppleScript — by string concatenation, typically — into a dictionary. Returns `nil` if the text isn't valid JSON, or is valid JSON that isn't an object. Used automatically by the `.json` return type. This is the route for nested structures that `parseSimpleAppleScriptRecord()` can't handle.

### `String.appleScriptFourCharCode` / `String.init(appleScriptFourCharCode:)`

```swift
public var appleScriptFourCharCode: FourCharCode?
public init(appleScriptFourCharCode code: FourCharCode)
```

Convert between an Apple event four-character code and its text. `"msng".appleScriptFourCharCode` gives the code `'msng'`; `String(appleScriptFourCharCode:)` gives `"msng"` back. The property returns `nil` unless the text is exactly four MacRoman-encodable characters.

Use the property to compare an `AppleScriptValue.constant` against a code from an application's dictionary:

```swift
if case .constant("autp".appleScriptFourCharCode) = value { … }
```

### `String.toPOSIXPath()`

```swift
public func toPOSIXPath() -> String?
```

Converts an HFS-style path (`Macintosh HD:Users:roger:Desktop`) to POSIX (`/Users/roger/Desktop`). Returns `nil` if the conversion fails.

### `String.toHFSPath()` / `URL.toHFSPath()`

```swift
public func toHFSPath() -> String?
```

The reverse: POSIX to HFS-style. The result starts with the name of the volume holding the file, so paths on external drives, disk images and network shares convert correctly. The path must exist — the volume is read from the file system — and `nil` comes back otherwise. The `URL` version delegates to the `String` one, so the two can't drift apart.

> [!NOTE]
> Most scriptable applications now expect POSIX paths, which are better passed as text and wrapped in the script with `POSIX file "$path"`. These conversions are here for the applications and script dialects that still want HFS paths.
