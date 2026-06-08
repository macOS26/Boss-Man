// Cocoa is an umbrella module on macOS over AppKit + Foundation + CoreData.
// We re-export AppKit so games written for macOS that `import Cocoa` resolve.
// Anything they need from Foundation comes through their own `import Foundation`
// against the Swift toolchain's Foundation (which is available in the WASI SDK).

@_exported import AppKit
