//
//  AppleScriptValue.swift
//  SwiftAppleScriptBridge
//
//  Created by Frédéric Simard on 2026-08-29.
//

import Foundation
import Carbon

extension AppleScriptBridge {

    // MARK: - APPLESCRIPT VALUES

    /// A script result carrying the type the script actually returned, rather than the one the caller declared.
    ///
    /// Every other `AppleScriptReturnType` coerces: declare `.int` and an answer of `missing value` becomes `0`,
    /// declare `.string` and a number becomes text. That is what you want almost always. Some properties,
    /// though, answer with a different *type* depending on state — the `value` of a cell in Numbers is a number,
    /// a date, text, a boolean, or `missing value` — and there the type is the information. Declaring
    /// `.wildCard` returns one of these cases instead, built from what the Apple event descriptor carried.
    ///
    /// ### Example:
    /// ```swift
    /// let result = try AppleScriptBridge.executeAppleScript(cellValue) as? AppleScriptBridge.AppleScriptValue
    ///
    /// switch result {
    ///     case .double(let number): print("number: \(number)")
    ///     case .string(let text):   print("text: \(text)")
    ///     case .missingValue:       print("the cell is empty")
    ///     default:                  break
    /// }
    /// ```
    ///
    /// - Note: `.unknown` carries the descriptor untouched, so a type this enum does not decode is still
    /// reachable. Pass it back through `init(descriptor:)` after coercing it yourself, or read it directly.
    public enum AppleScriptValue: Equatable {

        /// A floating-point number (`typeIEEE64BitFloatingPoint` and its 32- and 128-bit siblings).
        ///
        /// AppleScript answers with a real for anything its 32-bit integer cannot hold, so a large whole number
        /// arrives here rather than in `.int`. Overflow yields `Double.infinity`, which is a real too.
        case double(Double)

        /// An integer (`typeSInt32` and the other signed and unsigned integer types).
        case int(Int)

        /// Text (`typeUnicodeText` and the other text types).
        case string(String)

        /// A boolean (`typeBoolean`, `typeTrue`, `typeFalse`).
        case bool(Bool)

        /// A date (`typeLongDateTime`).
        case date(Date)

        /// A file (`typeFileURL`, `typeAlias`, `typeBookmarkData`), as the URL it resolves to.
        case fileURL(URL)

        /// AppleScript's `missing value`, which arrives as `typeType` carrying `cMissingValue`.
        case missingValue

        /// A constant (`typeEnumerated`, `typeType`, `typeProperty`, `typeKeyword`), as its raw four-character code.
        ///
        /// There is no general mapping from a code to a meaning: what `'autp'` means is defined by the
        /// application's dictionary, not by AppleScript. The code is therefore handed over as it is, for the
        /// caller to compare against the codes its target application documents — `String`'s
        /// `appleScriptFourCharCode` turns `"autp"` into one.
        case constant(FourCharCode)

        /// A list (`typeAEList`), decoded item by item.
        case list([AppleScriptValue])

        /// A record (`typeAERecord`), decoded field by field.
        ///
        /// Keys the caller wrote in the script come through by name. Keys AppleScript recognizes as its own
        /// terminology are compiled to four-character codes before the script ever runs, and come through as
        /// that code's text: `{name:"Roger"}` decodes as `["pnam": .string("Roger")]`, not as `["name": …]`.
        /// The same applies to the properties an application returns, which are terminology throughout.
        case record([String: AppleScriptValue])

        /// A descriptor of a type this enum does not decode, preserved as it arrived.
        case unknown(NSAppleEventDescriptor)
    }
}

// MARK: - DECODING DESCRIPTORS

extension AppleScriptBridge.AppleScriptValue {

    /// Builds a value from an Apple event descriptor, recursively.
    ///
    /// The descriptor's own `descriptorType` decides the case, so nothing is coerced: a script answering
    /// `missing value` yields `.missingValue`, not `0` or `""`. Lists and records are decoded eagerly, their
    /// items going back through this initializer, so nesting works to any depth. A descriptor whose type is not
    /// handled — or one that is, but whose value cannot be read — yields `.unknown`, carrying the descriptor
    /// itself so nothing is lost.
    ///
    /// - Parameter descriptor: The descriptor to decode, as returned by `NSAppleScript.executeAndReturnError`.
    public init(descriptor: NSAppleEventDescriptor) {
        switch descriptor.descriptorType {
            case typeIEEE32BitFloatingPoint, typeIEEE64BitFloatingPoint, type128BitFloatingPoint:
                self = .double(descriptor.doubleValue)

            case typeSInt16, typeUInt16, typeSInt32, typeUInt32, typeSInt64, typeUInt64:
                self = Self.integer(from: descriptor).map { .int($0) } ?? .unknown(descriptor)

            case typeBoolean, typeTrue, typeFalse:
                self = .bool(descriptor.booleanValue)

            case typeUnicodeText, typeUTF8Text, typeUTF16ExternalRepresentation, typeChar, typeCString:
                self = descriptor.stringValue.map { .string($0) } ?? .unknown(descriptor)

            case typeLongDateTime:
                self = descriptor.dateValue.map { .date($0) } ?? .unknown(descriptor)

            case typeFileURL, typeAlias, typeBookmarkData:
                self = descriptor.fileURLValue.map { .fileURL($0) } ?? .unknown(descriptor)

            case typeType, typeEnumerated, typeProperty, typeKeyword:
                // `enumCodeValue` and `typeCodeValue` read the same four bytes; either serves all four types.
                let code = descriptor.typeCodeValue
                self = code == FourCharCode(cMissingValue) ? .missingValue : .constant(code)

            case typeAEList:
                self = .list(Self.items(of: descriptor).map { AppleScriptBridge.AppleScriptValue(descriptor: $0) })

            case typeAERecord:
                self = .record(Self.fields(of: descriptor))

            default:
                self = .unknown(descriptor)
        }
    }

    /// Reads an integer descriptor as an `Int`, whatever its width and signedness.
    ///
    /// `int32Value` coerces to `typeSInt32` and answers `0` when the value does not fit, which turns a
    /// `typeSInt64` or a large `typeUInt32` into a silent zero. The bytes are therefore decoded by the width
    /// the descriptor's own type declares. They are laid out in the host's byte order, since the descriptor
    /// was built in this process.
    ///
    /// - Parameter descriptor: The integer descriptor to read.
    /// - Returns: The value as an `Int`, or `nil` if the data is short or the value is too large for an `Int`,
    /// in which case the caller falls back to `.unknown` rather than reporting a wrong number.
    private static func integer(from descriptor: NSAppleEventDescriptor) -> Int? {
        let data = descriptor.data

        func value<Integer: FixedWidthInteger>(_ type: Integer.Type) -> Int? {
            guard data.count >= MemoryLayout<Integer>.size else { return nil }
            return Int(exactly: data.withUnsafeBytes { $0.loadUnaligned(as: Integer.self) })
        }

        switch descriptor.descriptorType {
            case typeSInt16 : return value(Int16.self)
            case typeUInt16 : return value(UInt16.self)
            case typeSInt32 : return value(Int32.self)
            case typeUInt32 : return value(UInt32.self)
            case typeSInt64 : return value(Int64.self)
            case typeUInt64 : return value(UInt64.self)
            default         : return nil
        }
    }

    /// Returns the items of a list descriptor, in order.
    ///
    /// Apple event lists are indexed from 1, and `numberOfItems` is signed, so the range is built defensively
    /// rather than from `1...numberOfItems`, which would trap on an empty list.
    ///
    /// - Parameter descriptor: The list descriptor to read.
    /// - Returns: Its item descriptors, skipping any index that answers `nil`.
    private static func items(of descriptor: NSAppleEventDescriptor) -> [NSAppleEventDescriptor] {
        (0..<max(descriptor.numberOfItems, 0)).compactMap { descriptor.atIndex($0 + 1) }
    }

    /// Decodes the fields of a record descriptor.
    ///
    /// An Apple event record keys its items by four-character code, so a record the caller wrote with names of
    /// its own could not be represented directly. AppleScript packs those into a single `keyASUserRecordFields`
    /// item holding an alternating list of names and values, which is unpacked here. A record can carry both:
    /// `{name:"Roger", age:42}` compiles `name` to the `'pnam'` property and leaves `age` as a user field.
    /// User fields are decoded last, so a user field named after a four-character code wins over the coded item
    /// — the name the caller wrote is the one they will look for.
    ///
    /// - Parameter descriptor: The record descriptor to read.
    /// - Returns: The record's fields, keyed by user-defined name or by four-character code.
    private static func fields(of descriptor: NSAppleEventDescriptor) -> [String: AppleScriptBridge.AppleScriptValue] {
        var fields: [String: AppleScriptBridge.AppleScriptValue] = [:]
        var userFields: NSAppleEventDescriptor?

        for index in 0..<max(descriptor.numberOfItems, 0) {
            guard let item = descriptor.atIndex(index + 1) else { continue }
            let keyword = descriptor.keywordForDescriptor(at: index + 1)

            guard keyword != FourCharCode(keyASUserRecordFields) else {
                userFields = item
                continue
            }
            fields[String(appleScriptFourCharCode: keyword)] = AppleScriptBridge.AppleScriptValue(descriptor: item)
        }

        guard let userFields else { return fields }

        // Names and values alternate, so each name at an odd index is paired with the item that follows it.
        for index in stride(from: 1, to: userFields.numberOfItems, by: 2) {
            guard let name = userFields.atIndex(index)?.stringValue,
                  let value = userFields.atIndex(index + 1) else { continue }
            fields[name] = AppleScriptBridge.AppleScriptValue(descriptor: value)
        }

        return fields
    }
}
