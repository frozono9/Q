# Portable CLI runtime components

The development packages include Swift 6.1.2 runtime libraries and their
dependencies. They do not contain the Mac application or its artwork.

- Swift standard library, Foundation, Dispatch and related libraries:
  Apache License 2.0 with Runtime Library Exception. The package includes the
  Swift license and any license/notice files supplied in the installed Windows
  runtime. Sources: https://github.com/swiftlang/swift/tree/swift-6.1.2-RELEASE
- ICU, when included by the Swift runtime: Unicode/ICU license. Source and
  notices: https://github.com/unicode-org/icu/blob/main/LICENSE
- Microsoft Visual C++ runtime, when included in the Windows runtime directory:
  Microsoft redistributable components under their applicable distribution terms.
  https://learn.microsoft.com/cpp/windows/redistributing-visual-cpp-files

These are internal development artifacts for validating P1. The complete
redistributable/license inventory, signing and supported-platform release policy
must be reviewed before public end-user distribution in P4.
