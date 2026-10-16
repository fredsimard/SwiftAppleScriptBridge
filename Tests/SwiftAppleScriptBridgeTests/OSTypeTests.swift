//
//  OSTypeTests.swift
//  SwiftAppleScriptBridge
//
//  Tests for the `.osType` return type: reading a four-character code out of a descriptor, and the two
//  execution methods' answers for it. The execution tests run self-contained scripts, which drive no
//  application and so need no Automation permission.
//

import XCTest
import Carbon
@testable import SwiftAppleScriptBridge

// MARK: - OSTYPE DECODING

final class OSTypeDecodingTests: XCTestCase {

    /// Verifies that all four constant-carrying descriptor types hand over their code as it is.
    func testConstantDescriptorsCarryTheirCode() throws {
        let code = try XCTUnwrap("dfap".appleScriptFourCharCode)
        XCTAssertEqual(NSAppleEventDescriptor(enumCode: code).appleScriptOSType, code)
        XCTAssertEqual(NSAppleEventDescriptor(typeCode: code).appleScriptOSType, code)
        XCTAssertEqual(try XCTUnwrap(descriptor(ofType: typeProperty, code: code)).appleScriptOSType, code)
        XCTAssertEqual(try XCTUnwrap(descriptor(ofType: typeKeyword, code: code)).appleScriptOSType, code)
    }

    /// Verifies that `missing value` reaches the caller as its own code rather than as `nil`, so a property
    /// that answers it can be told from one this method could not read.
    func testMissingValueArrivesAsItsCode() {
        let descriptor = NSAppleEventDescriptor(typeCode: FourCharCode(cMissingValue))
        XCTAssertEqual(descriptor.appleScriptOSType, FourCharCode(cMissingValue))
    }

    /// Verifies that a descriptor carrying no constant answers `nil`, rather than the code `enumCodeValue`
    /// would read out of unrelated bytes — `42` would otherwise arrive as the code `'\0\0\0*'`.
    func testNonConstantDescriptorsYieldNil() {
        XCTAssertNil(NSAppleEventDescriptor(int32: 42).appleScriptOSType)
        XCTAssertNil(NSAppleEventDescriptor(double: 3.5).appleScriptOSType)
        XCTAssertNil(NSAppleEventDescriptor.list().appleScriptOSType)
        // A constant-typed descriptor carrying nothing reads as four NUL bytes, which is not a code either.
        XCTAssertNil(NSAppleEventDescriptor(descriptorType: typeEnumerated, data: nil)?.appleScriptOSType)
    }

    /// Verifies that nothing is coerced, text of exactly four characters included. `coerce(toDescriptorType:)`
    /// accepts some of these, but only where the process has the coercion handlers for it: `"dfap"` yields
    /// `'dfap'` in a user session and nothing on a headless CI runner, which is why the type decides instead.
    func testCoercibleDescriptorsAreNotCoerced() {
        XCTAssertNil(NSAppleEventDescriptor(string: "dfap").appleScriptOSType)
        XCTAssertNil(NSAppleEventDescriptor(string: "APFS format").appleScriptOSType)
        XCTAssertNil(NSAppleEventDescriptor(boolean: true).appleScriptOSType)
    }

    /// Builds a descriptor of a given type carrying a four-character code, for the two types
    /// `NSAppleEventDescriptor` has no convenience initializer for.
    ///
    /// - Parameters:
    ///   - type: The descriptor type to build.
    ///   - code: The code it carries, written in the host's byte order, as a descriptor built in-process is.
    /// - Returns: The descriptor, or `nil` if it could not be built.
    private func descriptor(ofType type: DescType, code: FourCharCode) -> NSAppleEventDescriptor? {
        var code = code
        return NSAppleEventDescriptor(descriptorType: type, bytes: &code, length: MemoryLayout<FourCharCode>.size)
    }
}

// MARK: - OSTYPE EXECUTION

final class OSTypeExecutionTests: XCTestCase {

    /// Runs a self-contained script through `NSAppleScript`, which drives no application and so needs no
    /// Automation permission, and returns what `.osType` decoded.
    private func osTypeResult(of source: String) throws -> FourCharCode? {
        let script = AppleScriptBridge.AppleScriptObject(name: "osType", returnType: .osType, script: source)
        return try AppleScriptBridge.executeAppleScript(script) as? FourCharCode
    }

    /// Verifies that a script answering with a class — a constant, as an application's enumerated properties
    /// are — comes back as the code itself, ready to compare against a dictionary's.
    func testAConstantResultArrivesAsItsCode() throws {
        XCTAssertEqual(try osTypeResult(of: "return class of 1"), try XCTUnwrap("long".appleScriptFourCharCode))
        XCTAssertEqual(try osTypeResult(of: #"return class of "x""#), try XCTUnwrap("ctxt".appleScriptFourCharCode))
        XCTAssertEqual(try osTypeResult(of: "return missing value"), FourCharCode(cMissingValue))
    }

    /// Verifies that a script answering with something that is not a constant yields `nil`, rather than a code
    /// assembled from whatever bytes the descriptor happened to carry.
    func testANonConstantResultYieldsNil() throws {
        XCTAssertNil(try osTypeResult(of: "return 42"))
        XCTAssertNil(try osTypeResult(of: #"return "APFS format""#))
        XCTAssertNil(try osTypeResult(of: #"return "dfap""#), "text is not coerced, however much it looks like a code")
    }
}

// MARK: - OSTYPE THROUGH THE COMMAND LINE

final class OSTypeCommandLineTests: XCTestCase {

    /// Verifies that `.osType` is refused by the command-line method, as `.wildCard` is and for the same
    /// reason: osascript prints the term, and the four-character code the caller asked for is nowhere in that
    /// text. The script is rejected before the process is launched, so it never runs.
    func testOSTypeIsRefused() {
        let script = AppleScriptBridge.AppleScriptObject(name: "osType", returnType: .osType, script: "return class of 1")
        XCTAssertThrowsError(try AppleScriptBridge.executeAppleScriptViaCommandLine(script)) { error in
            guard case AppleScriptBridge.AppleScriptError.unsupportedReturnType(.osType) = error else {
                return XCTFail("Expected .unsupportedReturnType(.osType), got \(error)")
            }
        }
    }
}
