---
title: "Non-hosted test target: SPM C module resolution and KolCore extraction pattern"
date: "2026-03-30"
last_updated: "2026-04-01"
category: build-errors
module: KolTests
problem_type: build_error
component: testing_framework
symptoms:
  - "xcodebuild test fails with 'Unable to resolve module dependency: FastClusterWrapper'"
  - "xcodebuild test fails with 'Unable to resolve module dependency: MachTaskSelfWrapper'"
  - "Undefined symbol in non-hosted test target for app-target types"
  - "TestStore tests crash with SEGV in hosted test bundle (TEST_HOST) on macOS 26 / Swift 6.2"
  - "@Shared(.fileStorage) triggers SEGV when TCA State is initialized in any test bundle"
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
  - tca
  - teststore
  - dependency-injection
---

# Non-hosted test target: SPM C module resolution and KolCore extraction pattern

## Problem

KolTests could not compile or link when run via `xcodebuild test`. Two sequential failures: (1) the Swift compiler could not resolve transitive C module dependencies from SPM packages, and (2) the linker could not find symbols defined in the Kol app target. The app itself built fine -- only the test target was broken. This was a pre-existing issue on `main`.

A subsequent, larger problem: TCA TestStore tests for TranscriptionFeature (the core reducer) could not run in any test bundle configuration due to Swift runtime bugs on macOS 26 / Swift 6.2.

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
  Undefined symbol: static Kol.<AppTargetType>.<method>(_:)
  Undefined symbol: nominal type descriptor for Kol.<AppTargetType>
  ```
- When TEST_HOST/BUNDLE_LOADER is added to run hosted tests: TestStore tests crash with SEGV during `@MainActor` class deallocation (swiftlang/swift#87316)
- When TEST_HOST is removed but TranscriptionFeature moved to KolCore: `TranscriptionFeature.State()` initialization crashes due to `@Shared(.fileStorage)` triggering file I/O that SEGVs in the test bundle context

## What Didn't Work

- **Cleaning DerivedData** (`rm -rf ~/Library/Developer/Xcode/DerivedData/Kol-*`) -- no effect. This is a project configuration issue, not a cache problem.
- **`xcodebuild -resolvePackageDependencies`** -- packages resolve fine. The test target simply doesn't declare them as dependencies.
- **Adding `SWIFT_INCLUDE_PATHS`** pointing to the C module `include/` directories -- the compiler still can't resolve the modules because SPM package products must be declared as target dependencies for their modulemaps to appear in the search path.
- **TEST_HOST + BUNDLE_LOADER** on KolTests to load the app binary -- hosted test bundle triggers swiftlang/swift#87316 (SEGV during `@MainActor` class deallocation in XCTest). Every TestStore test crashes and takes down the entire test process.
- **EmptyReducer guard** in `KolApp.appStore` when `isTesting` -- avoids live AppFeature effects but doesn't prevent the runtime deallocation crash.
- **Comprehensive dependency mocking** (all 18 `@Dependency` clients mocked) -- the crash occurs during TestStore/Store deallocation, not during execution. Mocking doesn't help.

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

### Fix 2: Extract testable logic into KolCore framework

KolTests is non-hosted (no `BUNDLE_LOADER` / `TEST_HOST`). It compiles against `.swiftmodule` files for type info but does not link the app target's `.o` files. Types in the Kol app target are visible at compile time but unresolvable at link time.

**Simple case — pure function extraction:**

Extract pure logic from an app-target client into a KolCore type. For example, vocabulary extraction logic lives in `KolCore/VocabularyExtractor.swift` — the app-target `ScreenContextClient` captures raw text, then delegates to the KolCore type for parsing. Tests import `@testable import KolCore` and call the extractor directly.

**Complex case — full reducer migration with dependency client split:**

Migrated TranscriptionFeature (the core TCA reducer, ~1150 lines, 18 dependencies) from the Kol app target to KolCore. This required splitting every dependency client into interface + implementation across the framework boundary.

**Pattern for each dependency client:**

```swift
// KolCore/Clients/FooClient.swift — interface (no AppKit)
@DependencyClient
public struct FooClient: Sendable {
    public var doThing: @Sendable (_ pid: pid_t) -> String? = { _ in nil }
}

extension FooClient: TestDependencyKey {
    public static let testValue = FooClient()
}

public extension DependencyValues {
    var foo: FooClient {
        get { self[FooClient.self] }
        set { self[FooClient.self] = newValue }
    }
}

// Kol/Clients/FooClient.swift — live implementation (AppKit OK)
import AppKit
import Dependencies
import KolCore

extension FooClient: DependencyKey {
    public static var liveValue: Self {
        Self(doThing: { pid in /* AppKit/AX implementation */ })
    }
}
```

**Clients split this way:** ScreenContextClient, WindowContextClient, IDEContextClient, EditTrackingClient, RecordingClient, TranscriptionClient, PasteboardClient, SoundEffectsClient, KeyEventMonitorClient, OCRClient, SleepManagementClient, TranscriptPersistenceClient (13 total). KeychainClient and LLMPostProcessingClient moved entirely to KolCore (no AppKit deps).

**New abstraction clients created** to replace direct AppKit/Carbon calls in the reducer:

```swift
// KolCore/Clients/WorkspaceClient.swift
public struct FrontmostApp: Sendable, Equatable {
    public var bundleIdentifier: String?
    public var localizedName: String?
    public var processIdentifier: pid_t
}

@DependencyClient
public struct WorkspaceClient: Sendable {
    public var frontmostApplication: @Sendable () -> FrontmostApp? = { nil }
}

// KolCore/Clients/InputSourceClient.swift
@DependencyClient
public struct InputSourceClient: Sendable {
    public var isHebrewKeyboardActive: @Sendable () -> Bool = { false }
}
```

**Also moved to KolCore:** SharedKeys.swift (`.kolSettings`, `.transcriptionHistory`, `.modelBootstrapState` persistence key definitions), StoragePaths.swift, ModelBootstrapState type.

Result after full migration: 250 tests pass, 0 failures, build succeeds.

## Why This Works

1. **Module resolution**: When the Swift compiler processes `@testable import Kol`, it must resolve ALL transitive module dependencies, including C modules from SPM packages. SPM only adds modulemap search paths for packages explicitly listed in a target's `packageProductDependencies`. Adding FluidAudio and WhisperKit makes the C modulemaps (`FastClusterWrapper`, `MachTaskSelfWrapper`) discoverable by the test target's compiler.

2. **Linker symbols**: Non-hosted test targets compile against the `.swiftmodule` (interface) but do not link the app binary's `.o` files. The KolCore framework IS linked into both the app and the test target. Moving pure logic into KolCore makes it linkable from tests while keeping app-target types as thin delegating wrappers.

3. **Interface/implementation split**: The `@DependencyClient struct` definition contains no platform-specific imports — just closure type signatures. The `DependencyKey` conformance with `liveValue` provides the real implementation with AppKit/Carbon/WhisperKit. TCA's dependency injection system resolves the correct implementation at runtime (live in the app, test value in tests).

4. **TestStore SEGV avoidance**: By not using TEST_HOST/BUNDLE_LOADER, the test process never loads the app binary, avoiding the `@MainActor` class deallocation crash (swiftlang/swift#87316).

## Known Limitation

Even after the migration, **TestStore tests crash with SEGV** when `TranscriptionFeature.State()` is initialized. The `@Shared(.fileStorage(...))` properties trigger file I/O via the Sharing framework's persistence layer, which SEGVs in the test bundle context. This appears to be the same family of Swift runtime bugs (swiftlang/swift#87316, #87422).

**Current workaround:** Test pure logic and type accessibility without TestStore. TestStore tests await a fix in the Swift runtime or TCA's Sharing framework.

**Potential future workaround:** Use `@Shared(.inMemory(...))` overrides for test state initialization, or provide a test-specific `State.init` that bypasses file storage.

## Prevention

1. **Test target imports**: New test files in KolTests must use `@testable import KolCore`, never `@testable import Kol`. The non-hosted test target cannot link symbols from the app target.

2. **Pure logic extraction**: When app-target code contains pure functions worth testing, extract them into KolCore as `public` types. The app-target file should delegate to the KolCore type.

3. **Dependency client split pattern**: When moving a TCA reducer to KolCore, split each `@DependencyClient` into interface (KolCore) + live implementation (Kol). Clients with no platform dependencies can move entirely to KolCore.

4. **Abstract platform calls**: Direct uses of `NSWorkspace`, `TISCopyCurrentKeyboardInputSource()`, or other platform APIs in reducer bodies must be wrapped in dependency clients before the reducer can move to KolCore.

5. **SPM packages with C targets**: When adding an SPM package that contains C/C++ wrapper targets (identifiable by `Sources/<name>/include/module.modulemap` in the package), add it to BOTH the app target AND the test target's `packageProductDependencies`.

6. **Diagnosis shortcut**: If `xcodebuild test` fails with "Unable to resolve module dependency" for a module you don't recognize, check whether it's an internal C target within one of your SPM dependencies: `find ~/Library/Developer/Xcode/DerivedData/*/SourcePackages/checkouts -name module.modulemap -path "*<module-name>*"`. Then add the parent SPM product to the test target's dependencies.

## Related Issues

- `docs/context-engineering.md` lines 910-922 — documents the KolCore extraction and test restructuring
- swiftlang/swift#87316 — `@MainActor` class deallocation crash in XCTest (open)
- swiftlang/swift#87422 — `swift_task_deinitOnExecutorImpl` crash with `@MainActor deinit` (open)
- CLAUDE.md "Build rules for agents" section — documents test-running commands and build workflow
