//
//  AppleScriptObject.swift
//  SwiftAppleScriptBridge
//
//  Created by Frédéric Simard on 2026-08-16.
//

import Foundation

extension AppleScriptBridge {

    // MARK: - APPLESCRIPT RETURN TYPES

    /// Represents the expected return type of an AppleScript execution.
    ///
    /// Use this enum to specify how the result of a script should be interpreted:
    /// - `int`: A 32-bit integer value returned by the script.
    /// - `string`: A string result.
    /// - `bool`: A boolean result, where non-zero is `true`, zero is `false`.
    /// - `list`: A list of strings, typically separated by carriage returns in AppleScript.
    /// - `record`: A simple AppleScript record parsed into a Swift dictionary (limited to flat key-value pairs).
    /// - `json`: A more reliable and flexible format for complex or nested records, returned as a Swift dictionary.
    /// - `wildCard`: Whatever the script returned, as an `AppleScriptValue` carrying its actual type rather than a declared one.
    /// - `none`: No return value is expected or needed.
    ///
    /// - Note: `.wildCard` is the one case that does not coerce. Use it for the properties that answer with a
    /// different type depending on state — a number most of the time, a constant such as `missing value`
    /// otherwise — where that type is itself the information. It needs the Apple event descriptor, which only
    /// `executeAppleScript(_:with:)` has; `executeAppleScriptViaCommandLine(_:with:)` throws on it.
    public enum AppleScriptReturnType: Sendable {
        case int
        case string
        case bool
        case list
        case record
        case json
        case wildCard
        case none
    }

    // MARK: - APPLESCRIPT RAW VALUES

    /// Wraps a value that is already valid AppleScript source and must be substituted into a script verbatim.
    ///
    /// Every `String` passed through `AppleScriptObject.variables` is escaped before substitution, so that
    /// filesystem-derived text (file paths, folder names, filenames) cannot terminate the surrounding string
    /// literal and inject arbitrary AppleScript. Values that are *meant* to be AppleScript code — an expression,
    /// or a terminology fragment built by the caller — must therefore be wrapped in this type to opt out of
    /// escaping. Lists and records need no wrapping: a Swift `Array` or `Dictionary` is rendered as one already.
    ///
    /// - Warning: Never wrap unvalidated user input in this type. Anything wrapped here is inserted into the
    /// script unchanged and is executed as code.
    ///
    /// ### Example:
    /// ```swift
    /// // Escaped: inserted as data inside a "..." literal.
    /// "theFilePath": url.path(percentEncoded: false)
    /// // Raw: inserted as AppleScript source.
    /// "theTarget": AppleScriptBridge.AppleScriptRawValue("front window")
    /// ```
    public struct AppleScriptRawValue: Sendable {

        /// The AppleScript source substituted verbatim in place of the placeholder.
        public let source: String

        /// Creates a raw value from a string that is already valid AppleScript source.
        /// - Parameter source: AppleScript source to substitute verbatim, without escaping.
        public init(_ source: String) {
            self.source = source
        }
    }

    // MARK: - APPLESCRIPT OBJECT

    /// A model representing an AppleScript script and its metadata.
    ///
    /// Use `AppleScriptObject` to encapsulate a script, a return type, a unique identifier, and optional variables for substitution. This structure provides methods to inject runtime variables and produce formatted script outputs for execution or debugging.
    ///
    /// - Properties:
    ///   - `name`: Mandatory. A unique name identifying the script. Useful for logging or display.
    ///   - `returnType`: The expected return type from the AppleScript execution. Defaults to `.none` if no value is provided.
    ///   - `variables`: An optional dictionary of predefined variables used to replace placeholders in the script. `String` values are escaped on substitution, and `Array` and `Dictionary` values are rendered as AppleScript lists and records; wrap AppleScript source in `AppleScriptRawValue` to insert it verbatim.
    ///   - `script`: Mandatory. The raw AppleScript source, with optional `$key` placeholders for dynamic substitution with elements in `variables` when using the `preparedScript` function. A placeholder holding text must be written inside a quoted literal (`"$key"`); one holding a number or a boolean must be written bare (`$key`).
    ///
    /// - Initializer:
    ///   - `init(name:returnType:variables:script:)`: Initializes a new script object with a name, return type, optional predefined variables and a script.
    ///
    /// - Methods:
    ///   - `preparedScript(with:):` Returns a version of the script with all `$key` placeholders replaced using both predefined and runtime variables, escaping every value except those wrapped in `AppleScriptRawValue`. Runtime values override predefined ones.
    ///   - `description():` Returns a human-readable multi-line string describing the script name, return type, variables, and source.
    public struct AppleScriptObject {

        /// A unique name identifying the script, used for logging and display.
        public let name: String

        /// The expected return type from the AppleScript execution.
        public let returnType: AppleScriptReturnType

        /// Predefined variables substituted into `$key` placeholders when the script is prepared.
        public let variables: [String: Any]?

        /// The raw AppleScript source, with optional `$key` placeholders.
        public let script: String

        /// Creates a script object.
        ///
        /// - Parameters:
        ///   - name: A unique name identifying the script, used for logging and display.
        ///   - returnType: How the script's result should be interpreted. Defaults to `.none`.
        ///   - variables: Predefined variables substituted into `$key` placeholders. Defaults to `nil`.
        ///   - script: The raw AppleScript source, with optional `$key` placeholders.
        public init(name: String, returnType: AppleScriptReturnType = .none, variables: [String: Any]? = nil, script: String) {
            self.name = name
            self.returnType = returnType
            self.variables = variables
            self.script = script
        }

        /// Returns the script with every `$key` placeholder replaced by its variable value.
        ///
        /// Predefined `variables` are merged with `runtimeVariables`, the latter winning on conflict. Each value
        /// is then rendered by `substitution(for:)`, which escapes text so it cannot break out of the AppleScript
        /// string literal it is substituted into.
        ///
        /// - Parameter runtimeVariables: Variables resolved at call time, overriding predefined ones of the same name.
        /// - Returns: The AppleScript source, ready to compile.
        public func preparedScript(with runtimeVariables: [String: Any]? = nil) -> String {

            // Combine predefined variables with runtime variables
            let combinedVariables = (variables ?? [:]).merging(runtimeVariables ?? [:]) { _, runtimeValue in
                runtimeValue // Runtime variable overrides predefined one
            }

            // Longest key first: `$page` would otherwise also match the start of `$pageNumber` and leave
            // a stray "Number" behind, depending on dictionary order.
            let keys = combinedVariables.keys.sorted(by: { $0.count > $1.count })

            // Single pass over the original script, so a substituted value is never itself scanned for
            // placeholders: a filename like `$folderPath.txt` stays intact.
            var preparedScript = ""
            var index = script.startIndex

            while index < script.endIndex {
                let afterDollar = script.index(after: index)
                guard script[index] == "$",
                      let key = keys.first(where: { script[afterDollar...].hasPrefix($0) }),
                      let value = combinedVariables[key] else {
                    preparedScript.append(script[index])
                    index = afterDollar
                    continue
                }
                preparedScript += Self.substitution(for: value)
                index = script.index(afterDollar, offsetBy: key.count)
            }

            return preparedScript
        }

        /// Renders a variable value as the text to substitute into the script.
        ///
        /// Text is escaped so that quotes and backslashes coming from file paths, folder names or filenames stay
        /// inside their AppleScript string literal instead of being parsed as code. Numbers and booleans are
        /// rendered as AppleScript literals, arrays and dictionaries as AppleScript lists and records, and
        /// `AppleScriptRawValue` is passed through untouched. Any other type is described and escaped, so an
        /// unforeseen type fails safe.
        ///
        /// - Parameters:
        ///   - value: The variable value to render.
        ///   - quotingText: Whether text carries its own quotation marks. A placeholder is written inside the
        ///   script's own quotes (`"$key"`), so a value substituted there must not add a second pair. An element
        ///   of a list or a record has no quotes around it in the script, so it has to supply its own. Defaults
        ///   to `false`.
        /// - Returns: The text to insert in place of the placeholder.
        private static func substitution(for value: Any, quotingText: Bool = false) -> String {
            let value = unwrappedNumber(value)

            /// Escapes text, adding the surrounding quotes only where the script does not already provide them.
            func text(_ string: String) -> String {
                quotingText ? "\"" + string.appleScriptStringEscaped + "\"" : string.appleScriptStringEscaped
            }

            switch value {
                case let raw        as AppleScriptRawValue : return raw.source
                case let string     as String              : return text(string)
                case let bool       as Bool                : return bool ? "true" : "false"
                case let int        as Int                 : return String(int)
                case let double     as Double              : return String(double)
                case let array      as [Any]               : return list(for: array)
                case let dictionary as [AnyHashable: Any]  : return record(for: dictionary)
                default                                    : return text(String(describing: value))
            }
        }

        /// Renders a Swift array as an AppleScript list.
        ///
        /// Elements go back through `substitution(for:)`, so escaping and literal rendering live in one place and
        /// nesting works: an array of dictionaries becomes a list of records.
        ///
        /// - Parameter array: The array to render.
        /// - Returns: An AppleScript list literal, `{}` if the array is empty.
        private static func list(for array: [Any]) -> String {
            "{" + array.map { substitution(for: $0, quotingText: true) }.joined(separator: ", ") + "}"
        }

        /// Renders a Swift dictionary as an AppleScript record.
        ///
        /// Values go back through `substitution(for:)`, so nesting works and escaping stays in one place. Keys are
        /// sorted, because a Swift dictionary is unordered and a script whose source changes from one run to the
        /// next is neither readable in a log nor testable. AppleScript records are unordered too, so sorting costs
        /// nothing. Sorting is on the key as written rather than on its rendered form, so quoting does not
        /// reorder anything. A key that is not a `String` is described first, which is what a dictionary bridged
        /// from Objective-C or from `JSONSerialization` needs.
        ///
        /// - Parameter dictionary: The dictionary to render.
        /// - Returns: An AppleScript record literal, `{}` if the dictionary is empty.
        ///
        /// - Note: AppleScript writes an empty record and an empty list the same way, as `{}`. An empty dictionary
        /// therefore renders as `{}`, and the script decides what to do with it.
        private static func record(for dictionary: [AnyHashable: Any]) -> String {
            let pairs = dictionary
                .map { (String(describing: $0.key), $0.value) }
                .sorted { $0.0 < $1.0 }
                .map { "\(recordKey(for: $0.0)):\(substitution(for: $0.1, quotingText: true))" }
            return "{" + pairs.joined(separator: ", ") + "}"
        }

        /// Renders a dictionary key as an AppleScript record key.
        ///
        /// AppleScript record keys are identifiers, not strings. A key that reads as a plain identifier is left
        /// bare, so that a term the target application defines keeps its meaning: `{name:"Roger"}` sets that
        /// application's `name` property, while `{|name|:"Roger"}` would define an unrelated property of the
        /// caller's own. Anything else — a key holding spaces or punctuation, or one of AppleScript's reserved
        /// words — is vertical-bar quoted, which is the only way such a key can be written at all.
        ///
        /// - Parameter key: The dictionary key, already converted to text.
        /// - Returns: The key as an AppleScript identifier, quoted only if it has to be.
        private static func recordKey(for key: String) -> String {
            let isPlainIdentifier = !key.isEmpty
                && key.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_") }
                && !(key.first?.isNumber ?? true)
                && !reservedWords.contains(key.lowercased())

            guard !isPlainIdentifier else { return key }

            // Inside vertical bars, a backslash escapes the character after it, so both it and the closing
            // bar have to be escaped for the key to survive intact.
            let escaped = key
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "|", with: "\\|")
            return "|" + escaped + "|"
        }

        /// AppleScript's reserved words, which cannot appear bare as a record key.
        ///
        /// Compared against the lowercased key, as AppleScript identifiers are case-insensitive. Multi-word
        /// operators (`apart from`, `out of`) cannot be written as a single identifier and are omitted.
        private static let reservedWords: Set<String> = [
            "about", "above", "after", "against", "and", "apart", "around", "as", "aside", "at",
            "back", "before", "beginning", "behind", "below", "beneath", "beside", "between", "but", "by",
            "considering", "contain", "contains", "continue", "copy", "div", "does", "eighth", "else", "end",
            "equal", "equals", "error", "every", "exit", "false", "fifth", "first", "for", "fourth",
            "from", "front", "get", "given", "global", "if", "ignoring", "in", "instead", "into",
            "is", "it", "its", "last", "local", "me", "middle", "mod", "my", "ninth",
            "not", "of", "on", "onto", "or", "out", "over", "prop", "property", "put",
            "ref", "reference", "repeat", "return", "returning", "script", "second", "set", "seventh", "since",
            "sixth", "some", "tell", "tenth", "that", "the", "then", "third", "through", "thru",
            "timeout", "times", "to", "transaction", "true", "try", "until", "where", "while", "whose",
            "with", "without"
        ]

        /// Unwraps an `NSNumber` into the Swift type it actually carries, leaving any other value untouched.
        ///
        /// An `NSNumber` bridges to `Bool` whatever it holds: `NSNumber(value: 1) as? Bool` is `true`. A count
        /// coming from `JSONSerialization` or from Objective-C would therefore match the boolean case in
        /// `substitution(for:)` and render as `true` instead of `1`. Only the CoreFoundation type tells a
        /// boolean from a number, so the check happens here, once, before any type matching.
        ///
        /// - Parameter value: The variable value to unwrap.
        /// - Returns: `Bool` for a CoreFoundation boolean, `Double` for a floating-point number, `Int` for any
        /// other number, or the value unchanged if it is not a number.
        private static func unwrappedNumber(_ value: Any) -> Any {
            guard let number = value as? NSNumber else { return value }
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
            return CFNumberIsFloatType(number as CFNumber) ? number.doubleValue : Int(number.int64Value)
        }

        /// Returns a human-readable, multi-line description of the script.
        ///
        /// - Returns: A string listing the script's name, return type, predefined variables and source.
        public func description() -> String {
            var desc = "AppleScript:\n\t- name: \(name)\n\t- returnType: \(returnType)"
            if let vars = variables, !vars.isEmpty { desc += "\n\t- variables: \(vars)" } else { desc += "\n\t- variables: none" }
            desc += "\n\t- script:\n\n\(script)\n"
            return desc
        }
    }
}
