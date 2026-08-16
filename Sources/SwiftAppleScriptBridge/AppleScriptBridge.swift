//
//  AppleScriptBridge.swift
//  SwiftAppleScriptBridge
//
//  Created by Frédéric Simard on 2026-08-16.
//

import Foundation
import Cocoa

/// A thin, typed bridge between Swift and AppleScript.
///
/// `AppleScriptBridge` compiles and runs `AppleScriptObject` scripts, escapes every substituted value so that
/// filesystem-derived text cannot inject AppleScript code, and parses the result into the Swift type declared
/// by the script's `returnType`.
///
/// - Note: The host application is responsible for the Apple Events permissions this class needs: the
/// `com.apple.security.automation.apple-events` entitlement, and an `NSAppleEventsUsageDescription` key in
/// its `Info.plist`. A package cannot supply either.
///
/// - Important: Sending Apple events constrains how the host application can be distributed. It cannot be
/// sandboxed, and therefore cannot ship on the Mac App Store. Signing with a Developer ID certificate and
/// notarizing for direct distribution is unaffected and works normally.
public class AppleScriptBridge: NSObject {

    // MARK: - LOGGING

    /// The closure invoked to log script sources and diagnostics.
    ///
    /// Defaults to printing in `DEBUG` builds only. Assign your own closure to route this into the host
    /// application's logging, or assign `nil` to silence the package entirely.
    ///
    /// - Parameters (of the closure):
    ///   - message: A short label describing what is being logged.
    ///   - details: The script source or other multi-line detail, possibly empty.
    public static var logHandler: ((_ message: String, _ details: String) -> Void)? = { message, details in
        #if DEBUG
        print("=============================================\r[DEBUG] : \(message)\r\(details)")
        #endif
    }

    /// Forwards a message to `logHandler`, if one is installed.
    ///
    /// - Parameters:
    ///   - message: A short label describing what is being logged.
    ///   - details: The script source or other multi-line detail. Defaults to an empty string.
    static func log(_ message: String, _ details: String = "") {
        logHandler?(message, details)
    }

    // MARK: - EXECUTE APPLESCRIPTS

    /// Executes the given `AppleScriptObject` and returns its result, based on the declared return type.
    ///
    /// This function compiles and runs the provided AppleScript synchronously using `NSAppleScript`,
    /// and interprets the result according to the script's declared `AppleScriptReturnType`.
    ///
    /// - Parameters:
    ///   - AppleScript: The `AppleScriptObject` to execute.
    ///   - runtimeVariables: Variables resolved at call time, overriding the object's predefined ones of the
    ///   same name. Defaults to `nil`.
    /// - Returns: The result of the script, cast to the expected type (`Int`, `String`, `Bool`, `[String]`,
    /// `[String: Any]`, or `nil`).
    /// - Throws:
    ///   - `AppleScriptError.failedToInitScript` if the script cannot be initialized.
    ///   - `AppleScriptError.executionError` if execution fails and returns an error.
    ///
    /// - Note: For `.list` and `.record`, raw strings are returned and may need further parsing.
    ///
    /// - Note: A script returning `0` yields `0`, not `nil`. Failure is reported by throwing, so callers can tell
    /// "the target app answered zero" from "the target app did not answer" — a distinction that open-document
    /// checks and similar state queries depend on.
    ///
    /// - Note: `NSAppleScript` is not thread-safe and must be used from the main thread. Calls arriving from any
    /// other thread are therefore marshalled onto the main queue and waited on, so that long-running loops which
    /// drive another application from a background queue stay correct. The main thread is blocked for the
    /// duration of each individual script, but is free between them to render progress updates.
    public static func executeAppleScript(_ AppleScript: AppleScriptObject, with runtimeVariables: [String: Any]? = nil) throws -> Any? {
        guard Thread.isMainThread else {
            return try DispatchQueue.main.sync { try executeAppleScript(AppleScript, with: runtimeVariables) }
        }

        guard let appleScript = NSAppleScript(source: AppleScript.preparedScript(with: runtimeVariables)) else {
            throw AppleScriptError.failedToInitScript
        }

        log("script [ \(AppleScript.name) ]", appleScript.source ?? "No source can be extracted.")

        var error: NSDictionary?
        let result = appleScript.executeAndReturnError(&error)

        if let error = error { throw AppleScriptError.executionError(String(describing: error)) }

        switch AppleScript.returnType {
            case .int:    return Int(result.int32Value)
            case .string: return result.stringValue
            case .bool:   return result.int32Value != 0 ? true : false
            case .list:   return result.stringValue?.components(separatedBy: .newlines)
            case .record: return result.stringValue?.parseSimpleAppleScriptRecord()
            case .json:   return result.stringValue?.parseJSONStringFromAppleScript()
            case .none:   return nil
        }
    }

    /// Executes the given `AppleScriptObject` using the `osascript` command-line tool and returns its result.
    ///
    /// This function runs the AppleScript externally via `Process` and reads its output from a pipe.
    /// It is an alternative to using `NSAppleScript`, and is especially useful for better sandbox compatibility or when avoiding `NSAppleScript` runtime quirks.
    ///
    /// - Parameters:
    ///   - AppleScript: The `AppleScriptObject` to execute.
    ///   - runtimeVariables: Variables resolved at call time, overriding the object's predefined ones of the
    ///   same name. Defaults to `nil`.
    /// - Returns: The result of the script, cast to the expected type (`Int`, `String`, `Bool`, `[String]`,
    /// `[String: Any]`, or `nil`).
    /// - Throws:
    ///   - `AppleScriptError.executionError` if the process fails to launch or run.
    ///   - `AppleScriptError.failedToReadOutput` if the output cannot be interpreted.
    ///
    /// - Note: For `.list` and `.record`, raw strings are returned and may need further parsing.
    ///
    /// - Note: Spawning `/usr/bin/osascript` is blocked by the App Sandbox. Use this only from a
    /// non-sandboxed application.
    ///
    /// - Note: The fully substituted script is passed to `osascript` as a command-line argument, where any
    /// local process can read it with `ps`. Prefer `executeAppleScript(_:with:)` if variables carry secrets.
    public static func executeAppleScriptViaCommandLine(_ AppleScript: AppleScriptObject, with runtimeVariables: [String: Any]? = nil) throws -> Any? {
        let process = Process()
        let pipe = Pipe()

        log("script", AppleScript.description())

        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", AppleScript.preparedScript(with: runtimeVariables)]
        process.standardOutput = pipe
        process.standardError = pipe

        let data: Data
        do {
            try process.run()
            // Read before waiting: osascript blocks writing once the pipe buffer fills,
            // and waitUntilExit() would then never return.
            data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
        } catch {
            throw AppleScriptError.executionError(String(describing: error))
        }

        guard let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw AppleScriptError.failedToReadOutput
        }

        switch AppleScript.returnType {
            case .int:    return Int(result)
            case .string: return result
            case .bool:   return result.caseInsensitiveCompare("true") == .orderedSame || (Int(result) ?? 0) != 0
            case .list:   return result.components(separatedBy: "\r")
            case .record: return result.parseSimpleAppleScriptRecord()
            case .json:   return result.parseJSONStringFromAppleScript()
            case .none:   return nil
        }
    }

    // MARK: - AUTOMATION PERMISSIONS (Apple Remote Events)

    /// Resets an application's Apple Events automation permission using `tccutil`.
    ///
    /// This function programmatically clears the app's authorization to control other apps via Apple Events.
    /// After calling this, macOS will prompt the user to re-authorize the app the next time automation is
    /// attempted.
    ///
    /// - Parameter bundleIdentifier: The bundle identifier of the application whose authorization is reset.
    /// Defaults to the host application's own identifier. If it cannot be read, the reset is skipped rather
    /// than run without a target, so that other applications' authorizations are never affected.
    /// - Returns: `true` if `tccutil` reset the authorization, `false` if the identifier was missing, the
    /// process failed to launch, or `tccutil` exited with a non-zero status.
    ///
    /// - Note: Spawning `/usr/bin/tccutil` is blocked by the App Sandbox, so this is only usable from a
    /// non-sandboxed application.
    @discardableResult
    public static func resetAutomationPermission(for bundleIdentifier: String? = Bundle.main.bundleIdentifier) -> Bool {
        guard let bundleIdentifier else {
            log("Failed to reset automation permissions: no bundle identifier.")
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "AppleEvents", bundleIdentifier]

        do {
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                log("Failed to reset automation permissions: tccutil exited with status \(process.terminationStatus).")
                return false
            }

            log("Automation permissions reset successfully.")
            return true
        } catch {
            log("Failed to reset automation permissions: " + String(describing: error))
            return false
        }
    }

    /// Requests automation permission by sending a harmless Apple event to the given application.
    ///
    /// This is used to force macOS to display the system prompt for automation access, typically after a reset
    /// or during initial setup. The script asks the target application to close the startup disk, which it
    /// cannot do — the attempt is enough to trigger the prompt, and the resulting error is swallowed by the
    /// script's own `try` block.
    ///
    /// - Parameters:
    ///   - bundleIdentifier: The bundle identifier of the application to request permission for, for example
    ///   `"com.apple.finder"`.
    ///   - activating: Whether the target application is brought to the foreground, which also launches it if
    ///   it is not already running. Defaults to `true`.
    /// - Returns: `true` if the probe script ran without error, `false` otherwise.
    ///
    /// - Note: Any error is logged through `logHandler` and does not affect app flow.
    @discardableResult
    public static func requestAutomationPermission(for bundleIdentifier: String, activating: Bool = true) -> Bool {
        let probe = AppleScriptObject(
            name: "authorizeAppleEvents",
            variables: ["appID": bundleIdentifier],
            script: """
                set sd to path to startup disk
                tell application id "$appID"
                    \(activating ? "activate" : "")
                    try
                        close sd -- will error
                    end try
                end tell
            """
        )

        do {
            _ = try executeAppleScript(probe)
            return true
        } catch let error as AppleScriptError {
            log(error.description)
            return false
        } catch {
            log("Unexpected error:\n" + String(describing: error))
            return false
        }
    }
}
