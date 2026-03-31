---
title: "SPM C module transitive dependency failures in non-hosted test target"
date: "2026-03-30"
category: build-errors
module: KolTests
problem_type: build_error
component: testing_framework
symptoms:
  - "xcodebuild test fails with 'Unable to resolve module dependency: FastClusterWrapper'"
  - "xcodebuild test fails with 'Unable to resolve module dependency: MachTaskSelfWrapper'"
  - "Undefined symbol: static Kol.WindowContextClient.looksLikePersonName in non-hosted test target"
  - "App target builds with zero errors; only test target fails"
root_cause: missing_include
resolution_type: dependency_update
severity: medium
related_components:
  - development_workflow
tags:
  - spm
  - c-module
  - modulemap
  - transitive-dependency
  - non-hosted-test
  - linker-error
  - fluidaudio
  - whisperkit
  - kolcore
---

# SPM C module transitive dependency failures in non-hosted test target

## Problem

KolTests could not compile or link when run via `xcodebuild test`. Two sequential failures: (1) the Swift compiler could not resolve transitive C module dependencies from SPM packages, and (2) the linker could not find symbols defined in the Kol app target. The app itself built fine -- only the test target was broken. This was a pre-existing issue on `main`.

## Symptoms

- `xcodebuild test -scheme Kol` fails immediately:
  ```
  Unable to resolve module dependency: 'FastClusterWrapper'
  Unable to resolve module dependency: 'MachTaskSelfWrapper'
  Testing cancelled because the build failed.
  ```
- `./scripts/build-install.sh --debug` succeeds with 0 errors (app target unaffected)
- Same failure on clean `main` branch (not caused by recent changes)
- After fixing module resolution, a second failure appears:
  ```
  Undefined symbol: static Kol.WindowContextClient.looksLikePersonName(_:)
  Undefined symbol: nominal type descriptor for Kol.WindowContextClient
  ```

## What Didn't Work

- **Cleaning DerivedData** (`rm -rf ~/Library/Developer/Xcode/DerivedData/Kol-*`) -- no effect. This is a project configuration issue, not a cache problem.
- **`xcodebuild -resolvePackageDependencies`** -- packages resolve fine. The test target simply doesn't declare them as dependencies.
- **Adding `SWIFT_INCLUDE_PATHS`** pointing to the C module `include/` directories -- the compiler still can't resolve the modules because SPM package products must be declared as target dependencies for their modulemaps to appear in the search path.

## Solution

### Fix 1: Add SPM package dependencies to the test target

Added FluidAudio and WhisperKit as `XCSwiftPackageProductDependency` entries in `Kol.xcodeproj/project.pbxproj`:

```
/* In the KolTests native target's packageProductDependencies array: */
packageProductDependencies = (
    47E05E012D444EE900D26DA6 /* ComposableArchitecture */,
    9B1137862CEB38C43538B9BE /* Dependencies */,
    D0046C259393F2A4938AB19A /* DependenciesMacros */,
    93CBD2F56664506274695FFE /* ConcurrencyExtras */,
    3B9944FCDBF0437F952241BC /* FluidAudio */,      /* added */
    F2A621BA7C114F699E1DE995 /* WhisperKit */,       /* added */
);
```

These reference the same `XCRemoteSwiftPackageReference` objects already used by the Kol app target.

### Fix 2: Extract testable logic into KolCore framework

KolTests is non-hosted (no `BUNDLE_LOADER` / `TEST_HOST`). It compiles against `.swiftmodule` files for type info but does not link the app target's `.o` files. Types in the Kol app target are visible at compile time but unresolvable at link time.

Extracted pure parsing logic from `Kol/Clients/WindowContextClient.swift` into `KolCore/NameParser.swift`:

```swift
// KolCore/NameParser.swift
public enum NameParser {
    public static func looksLikePersonName(_ text: String) -> Bool { ... }
    public static func parseNamesFromDescription(_ description: String) -> [String] { ... }
}
```

`WindowContextClient` delegates to `NameParser`. Tests import `@testable import KolCore` and call `NameParser` directly.

Result: 227 tests pass, 0 failures.

## Why This Works

1. **Module resolution**: When the Swift compiler processes `@testable import Kol`, it must resolve ALL transitive module dependencies, including C modules from SPM packages. SPM only adds modulemap search paths for packages explicitly listed in a target's `packageProductDependencies`. Adding FluidAudio and WhisperKit makes the C modulemaps (`FastClusterWrapper`, `MachTaskSelfWrapper`) discoverable by the test target's compiler.

2. **Linker symbols**: Non-hosted test targets compile against the `.swiftmodule` (interface) but do not link the app binary's `.o` files. The KolCore framework IS linked into both the app and the test target. Moving pure logic into KolCore makes it linkable from tests while keeping the app-target type (`WindowContextClient`) as a thin delegating wrapper.

## Prevention

1. **Test target imports**: New test files in KolTests must use `@testable import KolCore`, never `@testable import Kol`. The non-hosted test target cannot link symbols from the app target.

2. **Pure logic extraction**: When app-target code contains pure functions worth testing, extract them into KolCore as `public` types. The app-target file should delegate to the KolCore type.

3. **SPM packages with C targets**: When adding an SPM package that contains C/C++ wrapper targets (identifiable by `Sources/<name>/include/module.modulemap` in the package), add it to BOTH the app target AND the test target's `packageProductDependencies`.

4. **Diagnosis shortcut**: If `xcodebuild test` fails with "Unable to resolve module dependency" for a module you don't recognize, check whether it's an internal C target within one of your SPM dependencies: `find ~/Library/Developer/Xcode/DerivedData/*/SourcePackages/checkouts -name module.modulemap -path "*<module-name>*"`. Then add the parent SPM product to the test target's dependencies.

## Related Issues

- `docs/context-engineering.md` lines 910-922 -- documents the KolCore extraction and test restructuring that created the non-hosted test architecture
- CLAUDE.md "Build rules for agents" section -- documents test-running commands and build workflow
