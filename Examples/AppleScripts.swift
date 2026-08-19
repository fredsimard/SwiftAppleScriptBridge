//
//  AppleScripts.swift
//  SwiftAppleScriptBridge — example
//
//  An example of the file layout suggested in the README: every script the app uses,
//  gathered in one place as `AppleScriptObject` values, each with a doc comment that
//  shows up in Quick Help wherever it is called.
//
//  These target the Finder, so they run on any Mac without extra software. Copy the
//  file into your own project and replace the bundle identifier and the scripts.
//
//  Swift 6 language mode: `AppleScriptObject` is not `Sendable`, so each `static let`
//  below needs `nonisolated(unsafe) static let` to compile. Swift 5 mode needs nothing.
//  See the README, and issue #2.
//
//  Not compiled as part of the package.
//

import Foundation
import SwiftAppleScriptBridge

/// Every AppleScript the app runs, in one place.
///
/// Scripts with `$key` placeholders take their values at call time, through the `with:`
/// parameter of `AppleScriptBridge.executeAppleScript(_:with:)`.
enum AppleScripts {

    /// The application these scripts drive. Keeping it in one constant means a move to
    /// another app, or another version of the same app, touches a single line.
    static let targetApp = "com.apple.finder"

    // MARK: - NO RETURN VALUE

    /// Brings the Finder to the front, launching it if necessary.
    ///
    /// - Returns: Nothing. `executeAppleScript` yields `nil` for `.none`.
    static let activateApp = AppleScriptBridge.AppleScriptObject(
        name: "activateApp",
        script: """
            tell application id "\(targetApp)"
                activate
            end tell
        """
    )

    /// Reveals an item in the Finder and brings the window forward.
    ///
    /// - Parameter itemPath: **SET AT RUNTIME**: POSIX path of the item to reveal.
    /// - Returns: Nothing.
    static let revealItem = AppleScriptBridge.AppleScriptObject(
        name: "revealItem",
        script: """
            tell application id "\(targetApp)"
                reveal (POSIX file "$itemPath" as alias)
                activate
            end tell
        """
    )

    // MARK: - INT

    /// Counts the Finder windows currently open.
    ///
    /// - Returns: An `Int`. `0` means no window is open — which is a real answer, not a
    /// failure. Failure is reported by throwing.
    static let countOpenWindows = AppleScriptBridge.AppleScriptObject(
        name: "countOpenWindows",
        returnType: .int,
        script: """
            tell application id "\(targetApp)"
                return count of windows
            end tell
        """
    )

    /// Counts the items directly inside a folder, without descending into it.
    ///
    /// - Parameter folderPath: **SET AT RUNTIME**: POSIX path of the folder to count.
    /// - Returns: An `Int` with the number of items.
    static let countItemsInFolder = AppleScriptBridge.AppleScriptObject(
        name: "countItemsInFolder",
        returnType: .int,
        script: """
            tell application id "\(targetApp)"
                return count of items of (POSIX file "$folderPath" as alias)
            end tell
        """
    )

    // MARK: - STRING

    /// Reads the name of the startup disk.
    ///
    /// - Returns: A `String` with the volume name.
    static let startupDiskName = AppleScriptBridge.AppleScriptObject(
        name: "startupDiskName",
        returnType: .string,
        script: """
            tell application id "\(targetApp)"
                return name of startup disk
            end tell
        """
    )

    /// Reads the POSIX path of the folder shown in the frontmost Finder window.
    ///
    /// - Returns: A `String` with the POSIX path, or an empty string when no window is open.
    static let frontWindowPath = AppleScriptBridge.AppleScriptObject(
        name: "frontWindowPath",
        returnType: .string,
        script: """
            tell application id "\(targetApp)"
                if (count of windows) is 0 then return ""
                return POSIX path of (target of front window as alias)
            end tell
        """
    )

    // MARK: - BOOL

    /// Reports whether an item exists on disk.
    ///
    /// - Parameter itemPath: **SET AT RUNTIME**: POSIX path of the item to look for.
    /// - Returns: A `Bool`.
    static let itemExists = AppleScriptBridge.AppleScriptObject(
        name: "itemExists",
        returnType: .bool,
        script: """
            tell application id "\(targetApp)"
                return exists (POSIX file "$itemPath")
            end tell
        """
    )

    /// Moves an item to the trash, reporting whether it worked.
    ///
    /// Returning `true` at the end of a `try` block, and `false` from the handler, is the
    /// simplest way to give Swift a yes-or-no answer about work the script performed.
    ///
    /// - Parameter itemPath: **SET AT RUNTIME**: POSIX path of the item to trash.
    /// - Returns: A `Bool`, `true` on success.
    static let trashItem = AppleScriptBridge.AppleScriptObject(
        name: "trashItem",
        returnType: .bool,
        script: """
            tell application id "\(targetApp)"
                try
                    delete (POSIX file "$itemPath" as alias)
                    return true
                on error
                    return false
                end try
            end tell
        """
    )

    // MARK: - LIST

    /// Lists the names of the items directly inside a folder.
    ///
    /// The script joins the names into one piece of text separated by line feeds, because
    /// that is what the `.list` return type splits on. Returning a real AppleScript list
    /// would not survive the trip.
    ///
    /// - Parameter folderPath: **SET AT RUNTIME**: POSIX path of the folder to read.
    /// - Returns: A `[String]` of item names, in Finder order.
    static let itemNamesInFolder = AppleScriptBridge.AppleScriptObject(
        name: "itemNamesInFolder",
        returnType: .list,
        script: """
            tell application id "\(targetApp)"
                set theNames to name of every item of (POSIX file "$folderPath" as alias)
            end tell

            set savedDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to linefeed
            set theResult to theNames as text
            set AppleScript's text item delimiters to savedDelimiters

            return theResult
        """
    )

    // MARK: - RECORD

    /// Reads a few properties of a single item.
    ///
    /// The record is assembled as text rather than returned as an AppleScript record, since
    /// that is the form `.record` parses. Keep it flat: nested records and lists are not
    /// supported — use `.json` for those.
    ///
    /// - Parameter itemPath: **SET AT RUNTIME**: POSIX path of the item to inspect.
    /// - Returns: A `[String: Any]` with `itemName` (`String`), `itemSize` (`Int`) and
    /// `isFolder` (`Bool`).
    static let itemProperties = AppleScriptBridge.AppleScriptObject(
        name: "itemProperties",
        returnType: .record,
        script: """
            tell application id "\(targetApp)"
                set theItem to (POSIX file "$itemPath" as alias)
                set theName to name of theItem
                set theSize to (size of theItem) as integer
                set theIsFolder to (class of theItem is folder)
            end tell

            return "{itemName:\\"" & theName & "\\", itemSize:" & theSize & ", isFolder:" & theIsFolder & "}"
        """
    )

    // MARK: - JSON

    /// Reads the same properties for every item in a folder, as nested JSON.
    ///
    /// `.record` only handles one flat record, so anything nested — a list of records, here —
    /// has to be built as a JSON string inside the script and parsed with `.json`.
    ///
    /// Note the `escapeText` handler: values coming from the file system can contain quotes
    /// and backslashes, and they have to be escaped on the way out just as the bridge escapes
    /// them on the way in. Skipping this produces JSON that fails to parse, and you get `nil`.
    ///
    /// - Parameter folderPath: **SET AT RUNTIME**: POSIX path of the folder to read.
    /// - Returns: A `[String: Any]` with `count` (`Int`) and `items`, an array of dictionaries
    /// carrying `name` and `size`.
    static let folderContentsAsJSON = AppleScriptBridge.AppleScriptObject(
        name: "folderContentsAsJSON",
        returnType: .json,
        script: """
            on escapeText(theText)
                set savedDelimiters to AppleScript's text item delimiters

                set AppleScript's text item delimiters to "\\\\"
                set theParts to text items of theText
                set AppleScript's text item delimiters to "\\\\\\\\"
                set theText to theParts as text

                set AppleScript's text item delimiters to "\\""
                set theParts to text items of theText
                set AppleScript's text item delimiters to "\\\\\\""
                set theText to theParts as text

                set AppleScript's text item delimiters to savedDelimiters
                return theText
            end escapeText

            tell application id "\(targetApp)"
                set theItems to every item of (POSIX file "$folderPath" as alias)
            end tell

            set theEntries to {}
            repeat with anItem in theItems
                tell application id "\(targetApp)"
                    set theName to name of anItem
                    set theSize to (size of anItem) as integer
                end tell
                set end of theEntries to "{\\"name\\":\\"" & escapeText(theName) & "\\",\\"size\\":" & theSize & "}"
            end repeat

            set savedDelimiters to AppleScript's text item delimiters
            set AppleScript's text item delimiters to ","
            set theArray to theEntries as text
            set AppleScript's text item delimiters to savedDelimiters

            return "{\\"count\\":" & (count of theEntries) & ",\\"items\\":[" & theArray & "]}"
        """
    )

    // MARK: - VARIABLES AND RAW VALUES

    /// Creates a folder inside a parent folder, showing how the three placeholder forms differ.
    ///
    /// `"$parentPath"` and `"$folderName"` are quoted, so they arrive as text with their quotes
    /// and backslashes already escaped by the bridge. `$revealAfter` is bare, so it arrives as a
    /// real AppleScript boolean and needs no coercion.
    ///
    /// - Parameter parentPath: **SET AT RUNTIME**: POSIX path of the parent folder.
    /// - Parameter folderName: **SET AT RUNTIME**: Name of the folder to create.
    /// - Parameter revealAfter: **SET AT RUNTIME**: Whether to reveal the new folder afterwards.
    /// - Returns: A `String` with the POSIX path of the new folder, or an empty string on failure.
    static let createFolder = AppleScriptBridge.AppleScriptObject(
        name: "createFolder",
        returnType: .string,
        script: """
            tell application id "\(targetApp)"
                try
                    set theParent to (POSIX file "$parentPath" as alias)
                    set theFolder to make new folder at theParent with properties {name:"$folderName"}
                    if $revealAfter then reveal theFolder
                    return POSIX path of (theFolder as alias)
                on error
                    return ""
                end try
            end tell
        """
    )

    /// Moves several items to a destination folder in a single script.
    ///
    /// The paths are passed as a Swift `[String]`, which the bridge renders as an AppleScript list
    /// with every element escaped. The placeholder is written bare — `$itemPaths`, not
    /// `"$itemPaths"` — because it renders as a list literal rather than as text. See
    /// `moveItems(_:to:)` below.
    ///
    /// - Parameter itemPaths: **SET AT RUNTIME**: POSIX paths of the items to move, as `[String]`.
    /// - Parameter destinationPath: **SET AT RUNTIME**: POSIX path of the destination folder.
    /// - Returns: An `Int` with the number of items moved.
    static let moveItems = AppleScriptBridge.AppleScriptObject(
        name: "moveItems",
        returnType: .int,
        script: """
            set thePaths to $itemPaths
            set movedCount to 0

            tell application id "\(targetApp)"
                set theDestination to (POSIX file "$destinationPath" as alias)
                repeat with aPath in thePaths
                    try
                        move (POSIX file aPath as alias) to theDestination
                        set movedCount to movedCount + 1
                    end try
                end repeat
            end tell

            return movedCount
        """
    )
}

// MARK: - CALLING THE SCRIPTS

/// Example call sites, showing how each return type comes back into Swift.
enum FinderTasks {

    /// Counts the items in a folder.
    ///
    /// - Parameter url: The folder to count.
    /// - Returns: The number of items, or `0` if the script failed.
    static func itemCount(in url: URL) -> Int {
        do {
            let result = try AppleScriptBridge.executeAppleScript(
                AppleScripts.countItemsInFolder,
                with: ["folderPath": url.path(percentEncoded: false)]
            )
            return result as? Int ?? 0
        } catch let error as AppleScriptBridge.AppleScriptError {
            print(error.description)
            return 0
        } catch {
            print(error.localizedDescription)
            return 0
        }
    }

    /// Lists the names of the items in a folder.
    ///
    /// - Parameter url: The folder to read.
    /// - Returns: The item names, or an empty array if the script failed.
    static func itemNames(in url: URL) -> [String] {
        let result = try? AppleScriptBridge.executeAppleScript(
            AppleScripts.itemNamesInFolder,
            with: ["folderPath": url.path(percentEncoded: false)]
        )
        return result as? [String] ?? []
    }

    /// Reads the name, size and kind of a single item.
    ///
    /// - Parameter url: The item to inspect.
    /// - Returns: A tuple of the item's name, size and whether it is a folder, or `nil` on failure.
    static func properties(of url: URL) -> (name: String, size: Int, isFolder: Bool)? {
        guard
            let result = try? AppleScriptBridge.executeAppleScript(
                AppleScripts.itemProperties,
                with: ["itemPath": url.path(percentEncoded: false)]
            ) as? [String: Any],
            let name = result["itemName"] as? String,
            let size = result["itemSize"] as? Int,
            let isFolder = result["isFolder"] as? Bool
        else { return nil }

        return (name, size, isFolder)
    }

    /// Reads every item in a folder as nested JSON.
    ///
    /// - Parameter url: The folder to read.
    /// - Returns: Each item's name and size, or an empty array on failure.
    static func contents(of url: URL) -> [(name: String, size: Int)] {
        guard
            let result = try? AppleScriptBridge.executeAppleScript(
                AppleScripts.folderContentsAsJSON,
                with: ["folderPath": url.path(percentEncoded: false)]
            ) as? [String: Any],
            let items = result["items"] as? [[String: Any]]
        else { return [] }

        return items.compactMap { entry in
            guard let name = entry["name"] as? String, let size = entry["size"] as? Int else { return nil }
            return (name, size)
        }
    }

    /// Moves several items to a destination folder.
    ///
    /// Shows a Swift collection crossing over as an AppleScript list: the `[String]` is rendered as
    /// `{"...", "..."}` with each path escaped on the way in, so a filename containing a quote
    /// cannot break out of its literal. Dictionaries cross over the same way, as records, and the
    /// two nest — an `[[String: Any]]` arrives as a list of records.
    ///
    /// `AppleScriptRawValue` is still there for source no type mapping covers, such as an
    /// expression or a terminology fragment the caller assembled:
    /// `"target": AppleScriptBridge.AppleScriptRawValue("front window")`.
    ///
    /// - Parameters:
    ///   - urls: The items to move.
    ///   - destination: The folder to move them into.
    /// - Returns: The number of items actually moved.
    static func moveItems(_ urls: [URL], to destination: URL) -> Int {
        let result = try? AppleScriptBridge.executeAppleScript(
            AppleScripts.moveItems,
            with: [
                "itemPaths": urls.map { $0.path(percentEncoded: false) },
                "destinationPath": destination.path(percentEncoded: false)
            ]
        )
        return result as? Int ?? 0
    }
}
