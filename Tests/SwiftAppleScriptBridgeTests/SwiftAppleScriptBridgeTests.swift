//
//  SwiftAppleScriptBridgeTests.swift
//  SwiftAppleScriptBridge
//
//  Tests cover the pure, deterministic parts of the bridge: escaping, placeholder substitution and result
//  parsing. Script execution itself is not tested, since it needs a scriptable application and a
//  user-granted Automation permission.
//

import XCTest
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

// MARK: - PATH CONVERSION

final class PathConversionTests: XCTestCase {

    /// Verifies that an HFS path round-trips to POSIX and back.
    func testHFSAndPOSIXRoundTrip() throws {
        let posix = "/Users/roger/Desktop"
        let hfs = try XCTUnwrap(posix.toHFSPath())
        XCTAssertTrue(hfs.hasSuffix(":Users:roger:Desktop"))
        XCTAssertEqual(hfs.toPOSIXPath(), posix)
    }

    /// Verifies that the `URL` overload agrees with the `String` one.
    func testURLOverloadMatchesStringOverload() {
        let url = URL(fileURLWithPath: "/Users/roger/Desktop")
        XCTAssertEqual(url.toHFSPath(), "/Users/roger/Desktop".toHFSPath())
    }
}
