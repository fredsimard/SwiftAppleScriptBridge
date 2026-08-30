//
//  SwiftAppleScriptBridgeTests.swift
//  SwiftAppleScriptBridge
//
//  Tests cover the pure, deterministic parts of the bridge: escaping, placeholder substitution and result
//  parsing. Script execution itself is not tested, since it needs a scriptable application and a
//  user-granted Automation permission. The one exception is `CommandLineExecutionTests`, which runs
//  self-contained scripts through `osascript`: they drive no application, so they need no permission.
//

import XCTest
import Carbon
@testable import SwiftAppleScriptBridge

// MARK: - ESCAPING

final class EscapingTests: XCTestCase {

    /// Verifies that a plain string is left untouched.
    func testPlainTextIsUnchanged() {
        XCTAssertEqual("/Users/roger/Desktop".appleScriptStringEscaped, "/Users/roger/Desktop")
    }

    /// Verifies that double quotes are escaped so they cannot terminate the surrounding literal.
    func testQuotesAreEscaped() {
        XCTAssertEqual(#"say "hi""#.appleScriptStringEscaped, #"say \"hi\""#)
    }

    /// Verifies that backslashes are escaped before quotes, so an escaped quote is not produced by accident.
    func testBackslashesAreEscapedFirst() {
        XCTAssertEqual(#"a\"#.appleScriptStringEscaped, #"a\\"#)
        XCTAssertEqual(#"a\"b"#.appleScriptStringEscaped, #"a\\\"b"#)
    }
}

// MARK: - PLACEHOLDER SUBSTITUTION

final class PreparedScriptTests: XCTestCase {

    /// Verifies that text variables are substituted and escaped inside their string literal.
    func testStringVariableIsEscapedOnSubstitution() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["path": #"/tmp/a"b"#],
            script: #"set p to "$path""#
        )
        XCTAssertEqual(script.preparedScript(), #"set p to "/tmp/a\"b""#)
    }

    /// Verifies that numbers and booleans are rendered as bare AppleScript literals.
    func testNumbersAndBooleansAreRenderedBare() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["count": 3, "flag": true, "ratio": 1.5],
            script: "$count $flag $ratio"
        )
        XCTAssertEqual(script.preparedScript(), "3 true 1.5")
    }

    /// Verifies that a raw value is inserted verbatim, without escaping.
    func testRawValueIsNotEscaped() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["list": AppleScriptBridge.AppleScriptRawValue(#"{a:"x", b:"y"}"#)],
            script: "set l to $list"
        )
        XCTAssertEqual(script.preparedScript(), #"set l to {a:"x", b:"y"}"#)
    }

    /// Verifies that a longer key is substituted before a shorter key that prefixes it.
    func testLongerKeysAreSubstitutedFirst() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["page": 1, "pageNumber": 42],
            script: "$page/$pageNumber"
        )
        XCTAssertEqual(script.preparedScript(), "1/42")
    }

    /// Verifies that runtime variables override predefined ones of the same name.
    func testRuntimeVariablesOverridePredefinedOnes() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["n": 1],
            script: "$n"
        )
        XCTAssertEqual(script.preparedScript(with: ["n": 2]), "2")
    }

    /// Verifies that a substituted value is not itself scanned for placeholders.
    func testSubstitutedValueIsNotRescanned() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["folderPath": "$name.txt", "name": "Roger"],
            script: #"set p to "$folderPath""#
        )
        XCTAssertEqual(script.preparedScript(), #"set p to "$name.txt""#)
    }

    /// Verifies that a number arriving as `NSNumber` is rendered as its value, not as a boolean.
    func testNSNumberIsNotRenderedAsBoolean() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["count": NSNumber(value: 1), "flag": NSNumber(value: true)],
            script: "$count $flag"
        )
        XCTAssertEqual(script.preparedScript(), "1 true")
    }

    /// Verifies the same for numbers coming out of `JSONSerialization`, the common source of `NSNumber`.
    func testJSONNumbersKeepTheirType() throws {
        let json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(#"{"count":1,"flag":true,"ratio":1.5}"#.utf8)) as? [String: Any]
        )
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: json,
            script: "$count $flag $ratio"
        )
        XCTAssertEqual(script.preparedScript(), "1 true 1.5")
    }

    /// Verifies that an unforeseen value type is described and escaped, rather than injected as code.
    func testUnknownTypeFailsSafe() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["v": URL(fileURLWithPath: #"/tmp/a"b"#)],
            script: "$v"
        )
        XCTAssertFalse(script.preparedScript().contains(#"a"b"#))
    }
}

// MARK: - COLLECTION SUBSTITUTION

final class CollectionSubstitutionTests: XCTestCase {

    /// Verifies that an array becomes an AppleScript list, with each element escaped.
    func testArrayBecomesList() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["files": ["a", #"b"c"#], "counts": [1, 2]],
            script: "$files $counts"
        )
        XCTAssertEqual(script.preparedScript(), #"{"a", "b\"c"} {1, 2}"#)
    }

    /// Verifies that a dictionary becomes an AppleScript record, with keys sorted for a stable source.
    func testDictionaryBecomesRecord() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["person": ["name": "Roger", "age": 42, "active": true]],
            script: "$person"
        )
        XCTAssertEqual(script.preparedScript(), #"{active:true, age:42, name:"Roger"}"#)
    }

    /// Verifies that collections nest: an array of dictionaries becomes a list of records.
    func testNestedCollections() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["items": [["id": "a", "tags": ["x", "y"]], ["id": "b", "tags": [] as [Any]]]],
            script: "$items"
        )
        XCTAssertEqual(script.preparedScript(), #"{{id:"a", tags:{"x", "y"}}, {id:"b", tags:{}}}"#)
    }

    /// Verifies that both an empty array and an empty dictionary render as `{}`, which is how AppleScript
    /// writes an empty list and an empty record alike.
    func testEmptyCollections() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["list": [] as [Any], "record": [:] as [String: Any]],
            script: "$list $record"
        )
        XCTAssertEqual(script.preparedScript(), "{} {}")
    }

    /// Verifies that a key which does not read as a plain identifier is vertical-bar quoted, and that a key
    /// which does is left bare so the target application's own terminology still applies.
    func testRecordKeysAreQuotedOnlyWhenNeeded() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["r": ["name": 1, "first name": 2, "set": 3, "2nd": 4, "_ok": 5]],
            script: "$r"
        )
        XCTAssertEqual(script.preparedScript(), "{|2nd|:4, _ok:5, |first name|:2, name:1, |set|:3}")
    }

    /// Verifies that a backslash and a vertical bar inside a quoted key are escaped, so the key cannot
    /// terminate its own quoting.
    func testRecordKeyQuotingIsEscaped() {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["r": [#"a|b\c"#: 1]],
            script: "$r"
        )
        XCTAssertEqual(script.preparedScript(), #"{|a\|b\\c|:1}"#)
    }

    /// Verifies that a dictionary bridged from Objective-C or from JSON is rendered as a record, with its
    /// numbers kept as numbers rather than read as booleans.
    func testBridgedDictionaryIsRendered() {
        let json = try? JSONSerialization.jsonObject(with: Data(#"{"count":1,"ok":true}"#.utf8))
        let script = AppleScriptBridge.AppleScriptObject(
            name: "test",
            variables: ["r": json as Any],
            script: "$r"
        )
        XCTAssertEqual(script.preparedScript(), "{count:1, ok:true}")
    }
}

// MARK: - RECORD PARSING

final class RecordParsingTests: XCTestCase {

    /// Verifies that a flat record is parsed into the closest Swift types.
    func testFlatRecordIsParsed() {
        let parsed = #"{name:"John Doe", age:42, active:true, ratio:1.5}"#.parseSimpleAppleScriptRecord()
        XCTAssertEqual(parsed?["name"] as? String, "John Doe")
        XCTAssertEqual(parsed?["age"] as? Int, 42)
        XCTAssertEqual(parsed?["active"] as? Bool, true)
        XCTAssertEqual(parsed?["ratio"] as? Double, 1.5)
    }

    /// Verifies that separators appearing inside a quoted value are treated as content, not structure.
    func testSeparatorsInsideQuotedValuesAreContent() {
        let parsed = #"{path:"/Volumes/Disk: 1/a,b.jpg", n:2}"#.parseSimpleAppleScriptRecord()
        XCTAssertEqual(parsed?["path"] as? String, "/Volumes/Disk: 1/a,b.jpg")
        XCTAssertEqual(parsed?["n"] as? Int, 2)
    }

    /// Verifies that escaped quotes and backslashes inside a value are resolved.
    func testEscapesInsideValuesAreResolved() {
        let parsed = #"{v:"a\"b\\c"}"#.parseSimpleAppleScriptRecord()
        XCTAssertEqual(parsed?["v"] as? String, #"a"b\c"#)
    }

    /// Verifies that an empty record yields an empty dictionary rather than a failure.
    func testEmptyRecordYieldsEmptyDictionary() {
        XCTAssertEqual(#"{}"#.parseSimpleAppleScriptRecord()?.isEmpty, true)
    }

    /// Verifies that text which is not a flat record is rejected.
    func testMalformedInputIsRejected() {
        XCTAssertNil("not a record".parseSimpleAppleScriptRecord())
        XCTAssertNil(#"{a:{b:1}}"#.parseSimpleAppleScriptRecord())     // nesting unsupported
        XCTAssertNil(#"{a:"unterminated}"#.parseSimpleAppleScriptRecord())
        XCTAssertNil(#"{:1}"#.parseSimpleAppleScriptRecord())          // empty key
    }
}

// MARK: - JSON PARSING

final class JSONParsingTests: XCTestCase {

    /// Verifies that a JSON object built inside AppleScript is decoded, including nested values.
    func testNestedJSONIsDecoded() {
        let parsed = #"{"a":1,"b":{"c":["x","y"]}}"#.parseJSONStringFromAppleScript()
        XCTAssertEqual(parsed?["a"] as? Int, 1)
        XCTAssertEqual((parsed?["b"] as? [String: Any])?["c"] as? [String], ["x", "y"])
    }

    /// Verifies that invalid JSON, or JSON that is not an object, yields `nil`.
    func testInvalidJSONYieldsNil() {
        XCTAssertNil("{not json".parseJSONStringFromAppleScript())
        XCTAssertNil("[1,2,3]".parseJSONStringFromAppleScript())
    }
}

// MARK: - WILDCARD VALUES

final class WildCardValueTests: XCTestCase {

    private typealias Value = AppleScriptBridge.AppleScriptValue

    /// Verifies that the scalar types come back as themselves, rather than coerced into a declared type.
    func testScalarDescriptorsKeepTheirType() {
        XCTAssertEqual(Value(descriptor: NSAppleEventDescriptor(double: 1.5)), .double(1.5))
        XCTAssertEqual(Value(descriptor: NSAppleEventDescriptor(int32: 42)), .int(42))
        XCTAssertEqual(Value(descriptor: NSAppleEventDescriptor(string: "hello")), .string("hello"))
        XCTAssertEqual(Value(descriptor: NSAppleEventDescriptor(boolean: true)), .bool(true))
        XCTAssertEqual(Value(descriptor: NSAppleEventDescriptor(boolean: false)), .bool(false))
    }

    /// Verifies that a date and a file arrive as `Date` and `URL`, not as the text they would coerce to.
    func testDatesAndFilesAreDecoded() {
        // Apple event dates carry whole seconds, so the reference date keeps the comparison exact.
        let date = Date(timeIntervalSinceReferenceDate: 0)
        XCTAssertEqual(Value(descriptor: NSAppleEventDescriptor(date: date)), .date(date))

        let url = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        XCTAssertEqual(Value(descriptor: NSAppleEventDescriptor(fileURL: url)), .fileURL(url))
    }

    /// Verifies that a 64-bit integer is read from its own bytes, rather than coerced to 32 bits and zeroed.
    func testWideIntegersAreReadAtTheirOwnWidth() throws {
        var wide = Int64(9_000_000_000)
        let descriptor = try XCTUnwrap(
            NSAppleEventDescriptor(descriptorType: typeSInt64, bytes: &wide, length: MemoryLayout<Int64>.size)
        )
        XCTAssertEqual(descriptor.int32Value, 0, "int32Value fails on this descriptor; that is what the decoding works around")
        XCTAssertEqual(Value(descriptor: descriptor), .int(9_000_000_000))
    }

    /// Verifies that a value too large for an `Int` yields the descriptor rather than a wrong number.
    func testUnrepresentableIntegerFallsBackToTheDescriptor() throws {
        var huge = UInt64.max
        let descriptor = try XCTUnwrap(
            NSAppleEventDescriptor(descriptorType: typeUInt64, bytes: &huge, length: MemoryLayout<UInt64>.size)
        )
        XCTAssertEqual(Value(descriptor: descriptor), .unknown(descriptor))
    }

    /// Verifies that `missing value` is recognized, rather than handed over as a bare four-character code.
    func testMissingValueIsItsOwnCase() {
        XCTAssertEqual(Value(descriptor: NSAppleEventDescriptor(typeCode: FourCharCode(cMissingValue))), .missingValue)
    }

    /// Verifies that an application-defined constant keeps its raw code, which is all the caller can compare.
    func testConstantsCarryTheirFourCharacterCode() throws {
        let code = try XCTUnwrap("autp".appleScriptFourCharCode)
        XCTAssertEqual(Value(descriptor: NSAppleEventDescriptor(enumCode: code)), .constant(code))
        XCTAssertEqual(Value(descriptor: NSAppleEventDescriptor(typeCode: code)), .constant(code))
    }

    /// Verifies that a list is decoded item by item, and that nesting works.
    func testListsAreDecodedRecursively() {
        let inner = NSAppleEventDescriptor.list()
        inner.insert(NSAppleEventDescriptor(string: "x"), at: 0)

        let list = NSAppleEventDescriptor.list()
        list.insert(NSAppleEventDescriptor(double: 1.5), at: 0)
        list.insert(NSAppleEventDescriptor(typeCode: FourCharCode(cMissingValue)), at: 0)
        list.insert(inner, at: 0)

        XCTAssertEqual(Value(descriptor: list), .list([.double(1.5), .missingValue, .list([.string("x")])]))
    }

    /// Verifies that an empty list yields an empty list rather than trapping on its index range.
    func testEmptyListIsDecoded() {
        XCTAssertEqual(Value(descriptor: NSAppleEventDescriptor.list()), .list([]))
    }

    /// Verifies that both halves of a record are decoded: the keys AppleScript compiled to four-character
    /// codes, and the user-defined ones it packed into `keyASUserRecordFields`.
    func testRecordsDecodeCodedAndUserKeys() throws {
        let userFields = NSAppleEventDescriptor.list()
        userFields.insert(NSAppleEventDescriptor(string: "age"), at: 0)
        userFields.insert(NSAppleEventDescriptor(int32: 42), at: 0)

        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(string: "Roger"), forKeyword: try XCTUnwrap("pnam".appleScriptFourCharCode))
        record.setDescriptor(userFields, forKeyword: FourCharCode(keyASUserRecordFields))

        XCTAssertEqual(Value(descriptor: record), .record(["pnam": .string("Roger"), "age": .int(42)]))
    }

    /// Verifies that a user-defined key wins over a coded one of the same text, since it is the name the
    /// caller wrote and therefore the one they will look for.
    func testUserKeysWinOverCodedKeys() throws {
        let userFields = NSAppleEventDescriptor.list()
        userFields.insert(NSAppleEventDescriptor(string: "pnam"), at: 0)
        userFields.insert(NSAppleEventDescriptor(string: "user"), at: 0)

        let record = NSAppleEventDescriptor.record()
        record.setDescriptor(NSAppleEventDescriptor(string: "coded"), forKeyword: try XCTUnwrap("pnam".appleScriptFourCharCode))
        record.setDescriptor(userFields, forKeyword: FourCharCode(keyASUserRecordFields))

        XCTAssertEqual(Value(descriptor: record), .record(["pnam": .string("user")]))
    }

    /// Verifies that an undecoded type is handed over as the descriptor itself, so nothing is lost.
    func testUnhandledTypeYieldsTheDescriptor() {
        let descriptor = NSAppleEventDescriptor(eventClass: kCoreEventClass, eventID: kAEOpenApplication, targetDescriptor: nil, returnID: 0, transactionID: 0)
        XCTAssertEqual(Value(descriptor: descriptor), .unknown(descriptor))
    }
}

// MARK: - WILDCARD EXECUTION

final class WildCardExecutionTests: XCTestCase {

    private typealias Value = AppleScriptBridge.AppleScriptValue

    /// Runs a self-contained script through `NSAppleScript`, which drives no application and so needs no
    /// Automation permission, and returns what `.wildCard` decoded.
    private func wildCardResult(of source: String) throws -> Value? {
        let script = AppleScriptBridge.AppleScriptObject(name: "wildCard", returnType: .wildCard, script: source)
        return try AppleScriptBridge.executeAppleScript(script) as? Value
    }

    /// Verifies that one script returning different types, as several application properties do, is decoded
    /// as those types rather than coerced into one.
    func testTheSameScriptCanAnswerWithDifferentTypes() throws {
        XCTAssertEqual(try wildCardResult(of: "return 1.5"), .double(1.5))
        XCTAssertEqual(try wildCardResult(of: "return 42"), .int(42))
        XCTAssertEqual(try wildCardResult(of: #"return "hello""#), .string("hello"))
        XCTAssertEqual(try wildCardResult(of: "return true"), .bool(true))
        XCTAssertEqual(try wildCardResult(of: "return missing value"), .missingValue)
    }

    /// Verifies that a whole number too large for AppleScript's 32-bit integer arrives as the real it is,
    /// rather than as the zero a `.int` script would report.
    func testLargeWholeNumbersArriveAsReals() throws {
        XCTAssertEqual(try wildCardResult(of: "return 3000000000"), .double(3_000_000_000))
    }

    /// Verifies that a record written in the script decodes with its user-defined keys, and that a key
    /// AppleScript owns as terminology arrives as the four-character code it was compiled to.
    func testRecordKeysDecodeAsWrittenOrAsTheirCode() throws {
        let result = try wildCardResult(of: #"return {name:"Roger", age:42, ratio:1.5}"#)
        XCTAssertEqual(result, .record(["pnam": .string("Roger"), "age": .int(42), "ratio": .double(1.5)]))
    }

    /// Verifies that a list keeps one type per item, which is the whole point of the case.
    func testListItemsKeepTheirOwnTypes() throws {
        let result = try wildCardResult(of: #"return {1, "two", 3.5, missing value}"#)
        XCTAssertEqual(result, .list([.int(1), .string("two"), .double(3.5), .missingValue]))
    }
}

// MARK: - COMMAND-LINE EXECUTION

final class CommandLineExecutionTests: XCTestCase {

    /// Verifies that a boolean result is read from the text osascript prints, rather than coerced from an
    /// integer it never writes.
    func testCommandLineBooleanResults() throws {
        let yes = AppleScriptBridge.AppleScriptObject(name: "yes", returnType: .bool, script: "return true")
        let no  = AppleScriptBridge.AppleScriptObject(name: "no", returnType: .bool, script: "return false")
        XCTAssertEqual(try AppleScriptBridge.executeAppleScriptViaCommandLine(yes) as? Bool, true)
        XCTAssertEqual(try AppleScriptBridge.executeAppleScriptViaCommandLine(no) as? Bool, false)
    }

    /// Verifies that a substituted list and record are valid AppleScript source: the script reads a value
    /// back out of each, which only compiles and runs if both rendered correctly.
    func testSubstitutedCollectionsCompileAndRun() throws {
        let script = AppleScriptBridge.AppleScriptObject(
            name: "collections",
            returnType: .string,
            variables: ["people": [["name": "Roger", "first name": "R"], ["name": "Sam", "first name": "S"]]],
            script: """
                set thePeople to $people
                set thePerson to item 1 of thePeople
                return (name of thePerson) & " " & (|first name| of thePerson)
            """
        )
        XCTAssertEqual(try AppleScriptBridge.executeAppleScriptViaCommandLine(script) as? String, "Roger R")
    }

    /// Verifies that `.wildCard` is refused here, since osascript prints text and the descriptor carrying the
    /// actual type never reaches this method.
    func testWildCardIsRefused() {
        let script = AppleScriptBridge.AppleScriptObject(name: "wildCard", returnType: .wildCard, script: "return 1.5")
        XCTAssertThrowsError(try AppleScriptBridge.executeAppleScriptViaCommandLine(script)) { error in
            guard case AppleScriptBridge.AppleScriptError.unsupportedReturnType(.wildCard) = error else {
                return XCTFail("Expected .unsupportedReturnType(.wildCard), got \(error)")
            }
        }
    }
}

// MARK: - PATH CONVERSION

final class PathConversionTests: XCTestCase {

    /// Verifies that an HFS path round-trips to POSIX and back.
    func testHFSAndPOSIXRoundTrip() throws {
        // An existing path: `toHFSPath()` reads the volume name and mount point from the file system.
        let posix = NSHomeDirectory()
        let hfs = try XCTUnwrap(posix.toHFSPath())
        let expectedSuffix = ":" + URL(fileURLWithPath: posix).pathComponents.dropFirst().joined(separator: ":")
        XCTAssertTrue(hfs.hasSuffix(expectedSuffix), "\(hfs) should end with \(expectedSuffix)")
        XCTAssertEqual(hfs.toPOSIXPath(), posix)
    }

    /// Verifies that the `URL` overload agrees with the `String` one.
    func testURLOverloadMatchesStringOverload() {
        let url = URL(fileURLWithPath: NSHomeDirectory())
        XCTAssertEqual(url.toHFSPath(), NSHomeDirectory().toHFSPath())
    }
}
