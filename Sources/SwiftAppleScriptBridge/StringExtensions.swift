//
//  StringExtensions.swift
//  SwiftAppleScriptBridge
//
//  Created by Frédéric Simard on 2026-08-16.
//

import Foundation

// MARK: - PATHS

extension String {

    /// Converts an HFS-style path (e.g., `Macintosh HD:Users:roger:Desktop`) to a POSIX path (e.g., `/Users/roger/Desktop`).
    ///
    /// This function uses Core Foundation to interpret the classic HFS path and return its POSIX equivalent.
    ///
    /// - Returns: A POSIX-style file system path as a `String`, or `nil` if the conversion fails.
    public func toPOSIXPath() -> String? {
        guard let fileURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, self as CFString?, CFURLPathStyle(rawValue: 1)!, self.hasSuffix(":")) else { return nil }
        return (fileURL as URL).path
    }

    /// Converts a POSIX path to an HFS-style path (e.g., `/Users/roger/Desktop` -> `Macintosh HD:Users:roger:Desktop`).
    ///
    /// - Returns: An HFS-style path, or `nil` if the startup disk name cannot be read.
    ///
    /// - Note: Recent versions of most scriptable applications expect POSIX paths, which are better passed as
    /// `POSIX file` specifiers. This is kept for the applications and script dialects that still want HFS paths.
    public func toHFSPath() -> String? {
        let posixURL = URL(fileURLWithPath: self)
        guard let volumeName = startupDiskName() else { return nil }
        let hfsPath = ([volumeName] + posixURL.pathComponents.dropFirst()).joined(separator: ":")
        return hfsPath
    }
}

extension URL {

    /// Converts a file URL path to an HFS-style path (e.g., `file:///Users/roger/Desktop` -> `Macintosh HD:Users:roger:Desktop`).
    ///
    /// Delegates to `String.toHFSPath()` so both conversions cannot drift apart.
    ///
    /// - Returns: An HFS-style path, or `nil` if the startup disk name cannot be read.
    public func toHFSPath() -> String? {
        return self.path(percentEncoded: false).toHFSPath()
    }
}

/// Retrieves the name of the macOS startup disk.
///
/// Reads the volume name straight from the root URL's resource values, which needs no subprocess and no
/// Automation permission.
///
/// - Returns: The name of the startup disk as a `String`, or `nil` if it cannot be read.
func startupDiskName() -> String? {
    do {
        return try URL(fileURLWithPath: "/").resourceValues(forKeys: [.volumeNameKey]).volumeName
    } catch {
        AppleScriptBridge.log("Error retrieving startup disk name: \(error)")
        return nil
    }
}

// MARK: - ESCAPING

extension String {

    /// Returns a copy of the string safe for embedding inside an AppleScript double-quoted string literal.
    ///
    /// Escapes backslashes first, then double-quote characters, which are the only two characters
    /// that require escaping inside AppleScript `"..."` literals. Apply this to every filesystem-derived
    /// value before substituting it into an AppleScript template string.
    ///
    /// - Returns: The escaped string.
    ///
    /// - Note: `AppleScriptObject.preparedScript(with:)` applies this automatically to every `String` variable,
    /// so it only needs to be called directly when building AppleScript source by hand — a record list destined
    /// for an `AppleScriptRawValue`, for instance.
    public var appleScriptStringEscaped: String {
        self.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }
}

// MARK: - RESULT PARSING

extension String {

    /// Parses a simple AppleScript record string into a Swift dictionary.
    ///
    /// This function assumes that the input is a string returned by AppleScript representing a simple record like:
    ///
    /// `{name:"John Doe", age:42, active:true}`.
    ///
    /// - Limitations:
    ///   - Keys must be alphanumeric.
    ///   - String values must be wrapped in double quotes (as AppleScript typically returns).
    ///   - Nested records or lists are not supported.
    ///
    /// The record is scanned directly rather than rewritten into JSON: colons and commas appear inside values —
    /// file paths and times especially — so text substitution cannot tell a separator from content.
    ///
    /// - Returns: A `[String: Any]` dictionary whose values are `String`, `Int`, `Double` or `Bool`, or `nil` if
    /// the text is not a flat record.
    public func parseSimpleAppleScriptRecord() -> [String: Any]? {
        let trimmed = self.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"), trimmed.hasSuffix("}") else { return nil }

        let body = trimmed.dropFirst().dropLast()
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }

        var result: [String: Any] = [:]
        var key = ""
        var value = ""
        var readingKey = true
        var inQuotes = false
        var escaped = false

        /// Stores the pair read so far, returning false if the key was empty.
        func commitPair() -> Bool {
            let trimmedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedKey.isEmpty else { return false }
            result[trimmedKey] = String.appleScriptScalar(from: value.trimmingCharacters(in: .whitespacesAndNewlines))
            key = ""
            value = ""
            readingKey = true
            return true
        }

        for character in body {
            if inQuotes {
                value.append(character)
                if escaped { escaped = false }
                else if character == "\\" { escaped = true }
                else if character == "\"" { inQuotes = false }
                continue
            }

            if readingKey {
                if character == ":" { readingKey = false } else { key.append(character) }
                continue
            }

            switch character {
                case "\""      : inQuotes = true ; value.append(character)
                case ","       : guard commitPair() else { return nil }
                case "{", "}"  : return nil // nested records and lists are not supported
                default        : value.append(character)
            }
        }

        guard !inQuotes else { return nil } // unterminated string
        guard commitPair() else { return nil }
        return result
    }

    /// Interprets a single AppleScript record value as the closest Swift type.
    ///
    /// - Parameter raw: The value text, still carrying its surrounding quotes if it was a string.
    /// - Returns: A `String` with escapes resolved, or a `Bool`, `Int` or `Double` for unquoted literals. Text
    /// that matches none of those is returned unchanged, so nothing is lost.
    private static func appleScriptScalar(from raw: String) -> Any {
        if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") {
            return String(raw.dropFirst().dropLast())
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        switch raw {
            case "true"  : return true
            case "false" : return false
            default      : return Int(raw) ?? Double(raw) ?? raw as Any
        }
    }

    /// Parses a JSON-formatted string returned by AppleScript into a Swift dictionary. This is for more complex records when `parseSimpleAppleScriptRecord` does not work. That means that the JSON needs to be created inside the AppleScript then passed as output.
    ///
    /// This function assumes that the input string is a valid JSON generated manually inside AppleScript (e.g., via string concatenation). It attempts to decode the JSON into a `[String: Any]` dictionary.
    ///
    /// - Returns: A `[String: Any]` dictionary if decoding succeeds, otherwise `nil`.
    public func parseJSONStringFromAppleScript() -> [String: Any]? {
        if let data = self.data(using: .utf8) {
            let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            return result
        }
        return nil
    }
}
