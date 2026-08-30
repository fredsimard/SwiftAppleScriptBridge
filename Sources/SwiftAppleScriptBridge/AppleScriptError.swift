//
//  AppleScriptError.swift
//  SwiftAppleScriptBridge
//
//  Created by Frédéric Simard on 2026-08-16.
//

import Foundation

extension AppleScriptBridge {

    // MARK: - APPLESCRIPT ERRORS

    /// Represents errors that may occur during the execution of an AppleScript.
    ///
    /// This enum defines various failure modes for AppleScript operations, including initialization issues, output parsing errors, execution failures with specific messages, and generic error reporting. Use them with `throw` and an Alert to display those messages to the user.
    ///
    /// - Cases:
    ///   - `failedToInitScript`: The script could not be initialized or compiled.
    ///   - `failedToReadOutput`: The script executed, but its output could not be read or parsed.
    ///   - `executionError(String)`: The script failed to execute properly, with an error message.
    ///   - `unsupportedReturnType(AppleScriptReturnType)`: The script declared a return type the execution method cannot produce.
    ///   - `genericMessage(String)`: A catch-all error with a custom message.
    ///
    /// - Property:
    ///   - `description`: A human-readable explanation of the error, suitable for logging.
    ///
    /// - Note: The package's messages are English only, by design. An application that presents these to users
    /// in another language should switch over the case and supply its own translated text, rather than display
    /// `description` directly.
    public enum AppleScriptError: Error {

        case failedToInitScript
        case failedToReadOutput
        case executionError(String)
        case unsupportedReturnType(AppleScriptReturnType)
        case genericMessage(String)

        /// A human-readable, English explanation of the error, suitable for logging or developer-facing display.
        public var description: String {
            switch self {
                case .failedToInitScript:                    return "Failed to initialize AppleScript script."
                case .failedToReadOutput:                    return "Failed to read AppleScript script result."
                case .executionError(let execErrorMessage):  return "AppleScript execution error:\n" + execErrorMessage
                case .unsupportedReturnType(let returnType): return "The .\(returnType) return type is not supported by this execution method."
                case .genericMessage(let genericMessage):    return "\(genericMessage)"
            }
        }
    }
}
