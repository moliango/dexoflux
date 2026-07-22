# Build & Dependency Integration (Tuist)

> Executable conventions for building this app and wiring dependencies.
> Learned from real failures on 2026-07-21 (SwiftSoup integration, new-file
> compile errors).

---

## Convention: Regenerate the project after adding/removing source files

**What**: Run `make generate` whenever a Swift file is created or deleted —
not only after editing `Project.swift`.

**Why**: Target sources use `.glob("dexo/**")` which Tuist resolves **at
generation time**. A file created after the last generation is not part of the
`.xcodeproj`, so the build fails with `cannot find 'NewType' in scope` even
though the file exists on disk.

**Symptom → Fix matrix**:

| Symptom | Cause | Fix |
|---------|-------|-----|
| `error: cannot find 'X' in scope` for a type that exists in a new file | file not in generated project | `make generate`, rebuild |
| Build settings/deps changes not picked up | stale project | `make generate` |

---

## Convention: Add packages that CookedHTML already depends on via SPM, never `.external`

**What**: To expose a package to the app target when the local
`Packages/CookedHTML` already pulls it transitively (e.g. SwiftSoup), declare
it in `Project.swift` `packages:` as `.remote(...)` with the **identical URL**
CookedHTML uses, and depend via `.package(product:)`.

```swift
// Correct (Project.swift)
packages: [
    .local(path: "Packages/CookedHTML"),
    .remote(
        url: "https://github.com/scinfu/SwiftSoup.git",   // must match CookedHTML/Package.swift exactly
        requirement: .upToNextMajor(from: "2.7.0")
    ),
],
// target deps
.package(product: "SwiftSoup"),
```

```swift
// Wrong — duplicates the package
.external(name: "SwiftSoup"),
```

**Why**: `.external` builds a second SwiftSoup target through Tuist's
Dependencies project while workspace SPM builds another for CookedHTML. Two
same-named targets write the same DerivedData outputs → Xcode fails with
`Multiple commands produce '...SwiftSoup.build/.../*.stringsdata'`. Same-URL
SPM references are deduplicated into one package instance.

**Validation**: after `make generate`, `grep SwiftSoup dexoflux.xcodeproj/project.pbxproj`
must show one `XCRemoteSwiftPackageReference` and no Tuist-external SwiftSoup
target.

---

## Convention: Verification is a simulator build, nothing heavier

**What**: After changes, verify with

```bash
# only when files were added/removed (or Project.swift changed)
make generate
xcodebuild build -workspace dexoflux.xcworkspace -scheme dexoflux \
  -destination 'platform=iOS Simulator,id=<simulator-udid>'
```

**Why**: The owner iterates on-device manually; full `xcodebuild test` takes
minutes and is opt-in only. `swiftc -parse` alone is NOT sufficient — it misses
scope/type errors and the new-file-not-in-project failure above.

**Don't**: deploy to a physical device, launch the app, or run the test suite
unless explicitly asked.
