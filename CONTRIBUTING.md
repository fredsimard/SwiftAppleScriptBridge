# Contributing

Contributions are welcome. This is a small project I maintain in my spare time, so responses may take a few days — no offence intended if it's quiet for a bit.

For a bug, open an issue with the prepared script and the error text; the template asks for what I'll need. For anything larger than a fix, open an issue before writing code, so we can agree on the shape of it before you spend the time.

A few things to know before you start:

- **Scope.** This is a general-purpose bridge. Anything specific to one application belongs in a layer on top of it, not in here.
- **No dependencies.** The package depends on Foundation and Cocoa, and I'd like to keep it that way.
- **macOS 13 and Swift 5 language mode.** The 1.x line stays there. Strict concurrency work is queued for 2.0 — see the versioning note in the README.
- **Documentation.** Every type and function gets a `///` comment covering what it does, its parameters and what it returns. If you change behaviour, update the comment in the same commit.
- **Tests.** Anything deterministic — escaping, substitution, parsing — should come with tests. Execution itself can't be tested without a scriptable app and a granted Automation permission, so don't worry about that part.
- **English.** Code, comments and package messages are English only.

Then the usual: fork, branch, `swift build && swift test`, and open a PR against `main` with focused commits.
