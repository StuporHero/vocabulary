# Slang Module Packaging — Sketch

> **Status:** Sketch / RFC-zero. Nothing here is decided. The point of this
> document is to surface the design dimensions, list candidate options with
> tradeoffs, and tag what must be settled before any code is written. Every
> section is open to revision in the next pass.

---

## 0. Frame

**Goal.** Define a packaging and distribution system for modules written in
the [Slang shading language](https://github.com/shader-slang/slang) so that
authors can publish reusable shader libraries (BRDFs, sampling utilities,
denoisers, neural-graphics primitives, etc.) and consumers can pull them into
real-time rendering and GPU-compute projects with reproducible builds.

**Non-goals (this pass).**

- Picking an implementation language for the tooling.
- Building anything. This is a paper exercise.
- Replicating every feature of mature ecosystems (Cargo, npm). Start small.

**Prior art at a glance.**

| System            | Identity            | Index         | Artifact storage | Resolver       | Notable property                      |
| ----------------- | ------------------- | ------------- | ---------------- | -------------- | ------------------------------------- |
| Cargo / crates.io | scoped + semver     | git index     | CDN tarballs     | PubGrub        | Source-only distribution              |
| npm               | scoped + semver     | hosted JSON   | CDN tarballs     | SAT-ish        | Hosted API, range-based               |
| Go modules        | URL-as-name         | proxy + sum   | proxy            | MVS            | URL identity, content-addressed sums  |
| vcpkg             | port + version      | git           | source builds    | range          | Source-builds per-toolchain           |
| Conan             | name/version@user   | hosted        | binary cache     | range          | Binary cache keyed on profile         |
| OCI registries    | repo + tag/digest   | registry API  | layered blobs    | n/a            | Generic, content-addressed            |
| Bazel BCR         | module + version    | git           | source + lock    | MVS            | Reproducible by design                |

**What Slang breaks vs. the above.**

- Compiled `.slang-module` artifacts are **compiler-version-locked**; IR is
  not yet stable. So binary distribution has to key on compiler version.
- A module declares **capability** requirements (SM level, raytracing, mesh
  shaders, wave ops, atomics on f16, …) — closer to Conan profiles than to
  Cargo features.
- Targets are plural: HLSL, SPIR-V, GLSL, Metal, WGSL, CUDA, C++. Some
  modules are target-agnostic; some are not.
- Generics + interfaces + link-time specialization mean a module's public API
  surface is richer than a function signature list — semver compatibility
  rules need a Slang-aware definition.
- **Consumers are usually not Slang programs**; they are C++/Rust engines
  invoking the Slang compiler. Host-build integration is part of the
  product, not an afterthought.

---

## 1. Glossary

Pinning these now to avoid bikeshedding later.

- **Module** — the unit Slang's `module` declaration names; one or more
  `.slang` source files compiled together.
- **Package** — the unit this registry distributes. A package may contain
  one or more modules (default: one).
- **Target** — a compilation backend (`hlsl`, `spirv`, `metal`, `wgsl`,
  `glsl`, `cuda`, `cpp`, `ptx`).
- **Capability** — a Slang-declared requirement (e.g. `sm_6_5`,
  `raytracing`, `mesh`, `wave_ops`).
- **Profile** — a `(compiler-version, target, capability-set)` triple
  against which an artifact is built.
- **Artifact** — a built blob (`.slang-module` or per-target intermediate)
  keyed by profile.
- **Index** — the registry's catalog of package metadata.
- **Lockfile** — a consumer-side pin of exact resolved package versions and
  artifact digests.

---

## 2. Per-dimension template

Each design dimension below uses this template:

> **Problem.** What's being decided.
> **Slang wrinkle.** What makes this different from the obvious prior-art answer.
> **Options.** A / B / C with tradeoffs.
> **Open questions.**
> **Tag.** `MUST-DECIDE-NOW` or `DEFER`.

---

## 3. Design dimensions

### 3.1 Identity & versioning &nbsp;&nbsp; `MUST-DECIDE-NOW`

**Problem.** How is a package named and versioned?

**Slang wrinkle.** Slang module names are flat identifiers (`import foo;`).
The package name and the module name need not be the same, but mapping rules
must be unambiguous. Public API surface includes generics, interfaces, and
associated types — small textual changes can be ABI-breaking even when they
look additive.

**Options.**

- **A. Flat name + semver.** `gbuffer-utils 0.4.1`. Easiest; collides on
  popular names.
- **B. Scoped name + semver.** `@nvidia/raytracing-utils 0.4.1`. Mirrors
  npm/Cargo conventions; cheap namespace ownership.
- **C. URL-as-name (Go-style) + semver.** `github.com/org/repo 0.4.1`.
  Decentralized; no central name registry needed; awkward for users.
- **D. Hybrid: semver in manifest, content digest in lockfile.** Layer on
  top of A/B/C. Probably required regardless of which name scheme wins.

**Open questions.**

- How does semver map onto Slang's surface? Proposal: a Slang-aware
  *signature digest* (over public functions, generic parameters, interface
  conformances) defines "did the API change", with semver as the human-facing
  promise.
- Pre-1.0 rules (Cargo treats `0.x.y` minor as breaking; npm doesn't).

---

### 3.2 Manifest format & required fields &nbsp;&nbsp; `MUST-DECIDE-NOW`

**Problem.** What does the per-package manifest look like and what does it
require?

**Slang wrinkle.** Beyond Cargo-style fields, a Slang manifest needs to
describe: the declared `module` name, supported targets, required
capabilities, min/max Slang compiler version, exported entry points (if
any), and exposed interfaces (for downstream conformance).

**Options.**

- **A. TOML** (Cargo-style). Human-friendly, comments, well-supported.
- **B. JSON** (npm-style). Machine-friendly, no comments, ubiquitous.
- **C. Slang-native syntax.** A `package` declaration inside Slang itself.
  Maximally idiomatic; needs compiler support and tooling churn.

**Strawman fields (format-agnostic).**

```
name              = "..."             # registry identity
version           = "x.y.z"
module            = "..."             # Slang module name; defaults to `name` munged
description       = "..."
license           = "SPDX-id"
authors           = [...]
repository        = "..."
keywords          = [...]

slang.min_version = ">=2025.1"        # compiler range
slang.max_version = "<2026.0"
targets           = ["hlsl", "spirv", "metal"]   # what the package supports
capabilities      = ["sm_6_5", "raytracing"]     # what the package requires
entry_points      = [ { name = "main_cs", stage = "compute" }, ... ]
exports.interfaces = ["IBRDF", "ISampler"]

dependencies      = { foo = ">=0.4, <0.5", bar = { version = "1.2", optional = true } }
features          = { rt = ["bar"] }             # Cargo-style optional features
```

**Open questions.**

- Are multi-module packages allowed in v0, or strictly one module per package?
- Are non-Slang assets (precomputed LUTs, ONNX weights for neural shaders)
  allowed inside a package?

---

### 3.3 Source vs. precompiled distribution &nbsp;&nbsp; `MUST-DECIDE-NOW`

**Problem.** Does the registry ship `.slang` sources, `.slang-module`
artifacts, or both?

**Slang wrinkle.** `.slang-module` is compiler-version-locked; the IR
format is not yet stable across Slang releases. Shipping artifacts means
shipping a matrix of `(package-version × compiler-version × target × caps)`
blobs.

**Options.**

- **A. Source-only.** Always compile on consumer side. Simplest registry;
  longest build times; no IR-stability concerns; matches Cargo.
- **B. Artifact-only per profile.** Registry holds `.slang-module` blobs
  keyed by `(compiler-version, target, capability-set)`. Fastest builds;
  large storage footprint; missing profile = build failure.
- **C. Sources canonical, artifacts as cache.** Source is the source of
  truth; pre-built artifacts are an optional speedup, fetched if the
  consumer's profile matches, otherwise compiled locally. Closer to a build
  cache than a binary distribution.

**Recommended frame.** Treat sources as canonical (C). Artifact cache is a
v1 optimization; the manifest and index need to allow it but the MVP can
ignore it.

**Open questions.**

- Does the registry ever distribute *only* artifacts (closed-source vendor
  shaders)? Probably yes eventually; out of scope for v0.

---

### 3.4 Compiler / target / capability matrix &nbsp;&nbsp; `DEFER` (depends on 3.3)

**Problem.** How does the index advertise which profiles a package version
supports?

**Options.**

- **A. Sparse explicit matrix.** Index entry lists every supported
  `(compiler, target, caps)` tuple. Precise; verbose; brittle across
  compiler releases.
- **B. Declared support ranges.** Author writes `targets = [...]`,
  `slang.min_version`, `capabilities = [...]`; the index advertises the
  declared range and lets the resolver intersect.
- **C. Build-on-demand.** Registry has a build farm; resolver requests a
  profile and the farm builds-or-caches. Heavyweight; defer indefinitely.

**Tag.** Deferred until 3.3 lands. If 3.3 = source-only or source-canonical,
option B suffices.

---

### 3.5 Dependency resolution & lockfile &nbsp;&nbsp; `DEFER`

**Problem.** Given a root manifest, produce a concrete, reproducible set of
package versions.

**Slang wrinkle.** Two extra axes flow through the graph: required Slang
compiler version (intersect across the graph), and required capabilities
(union — the consuming pipeline must satisfy the union).

**Options.**

- **A. MVS (Go-style).** Always pick the *minimum* version that satisfies
  all constraints. Reproducible without a lockfile. Less flexible.
- **B. SAT-style (npm).** Solve constraints; allow multiple major versions
  side-by-side. Complex; Slang doesn't currently support two same-named
  modules in one program.
- **C. PubGrub (Cargo / pub).** Single-version-per-name; high-quality error
  reporting. Likely the right answer if Slang stays single-version.

**Lockfile.** Required regardless. Pin `(name, version, digest, profile)`.

**Tag.** Deferred until identity + manifest land.

---

### 3.6 Registry architecture &nbsp;&nbsp; `MUST-DECIDE-NOW`

**Problem.** Where does the index live and how is it served?

**Options.**

- **A. Git-backed index (crates.io model).** Index is a git repo of small
  JSON/TOML files, one per package; publishers push commits via an API.
  Easy mirroring, cacheable, offline-friendly. Doesn't scale to millions of
  packages, but Slang won't have millions.
- **B. Hosted JSON API (npm model).** Custom service. Maximum flexibility;
  requires running infrastructure from day one.
- **C. Static CDN blob (Go module proxy).** Index is a tree of files in
  object storage; clients GET predictable URLs. Cheap; harder to mutate
  atomically.
- **D. Reuse OCI.** Packages as OCI artifacts in any container registry.
  Free auth, mirroring, and CDN; awkward UX, semver layered on top of tags.

**Recommended frame.** A or D. A is more conventional and easier to bootstrap
in a single repo. D is interesting if Slang packages ever want to live next
to container images in existing infrastructure.

**Open questions.**

- Self-hosting story for private registries (almost certainly required for
  game studios / IHVs).

---

### 3.7 Publishing & auth &nbsp;&nbsp; `DEFER`

**Problem.** Who can publish what, and how is provenance established?

**Options sketch.**

- Account-per-publisher with API tokens (crates.io).
- Org-scoped names with per-org keys.
- Sigstore-style keyless signing tied to OIDC identities.
- Yank vs. delete: yank-only (crates.io), or both (npm). Yank-only is
  safer for downstream reproducibility.

Deferred until index format is chosen.

---

### 3.8 CLI surface &nbsp;&nbsp; `DEFER`

Likely commands:

| Command                     | Behavior                                            |
| --------------------------- | --------------------------------------------------- |
| `slangpm init`              | Scaffold a package manifest in cwd.                 |
| `slangpm add <name>[@ver]`  | Add a dependency, update lockfile.                  |
| `slangpm install`           | Materialize dependencies from lockfile.             |
| `slangpm update [<name>]`   | Recompute lockfile within constraints.              |
| `slangpm publish`           | Validate, package, upload to registry.              |
| `slangpm yank <name@ver>`   | Mark a version unselectable for new resolutions.    |
| `slangpm search <query>`    | Query the index.                                    |
| `slangpm vendor`            | Materialize dependencies into the source tree.      |
| `slangpm export --format=…` | Emit CMake / Bazel / pkg-config descriptors (3.10). |

**Open question.** Standalone `slangpm` binary, or fold into `slangc`
itself? Standalone is easier to ship independently of compiler releases.

---

### 3.9 Security & trust &nbsp;&nbsp; `DEFER`

- Manifest signing (Sigstore / minisign / age).
- Declared `capabilities` doubles as an audit signal — a denoiser package
  shouldn't be requesting raytracing capabilities.
- **No build scripts in v0.** Packages are declarative; no arbitrary code
  executed at install time. This single decision eliminates most of the
  npm-style supply-chain attack surface.
- Hash-pinned lockfiles (3.5) make tampering detectable.

---

### 3.10 Host build-system integration &nbsp;&nbsp; `DEFER`, but v1-blocking

**Problem.** A C++ Vulkan engine using Slang wants to consume a resolved
dependency set. It probably uses CMake, Bazel, or a custom build.

**Options.**

- **A. Emit native descriptors.** `slangpm export --format=cmake`
  generates a `slang-deps.cmake` with include paths, search paths,
  per-target compile flags, and a target named `Slang::deps`.
- **B. Single index file.** Emit a JSON describing the resolved set; let
  each build system parse it via a small adapter.
- **C. Compiler-driven.** `slangc` learns to read a lockfile directly and
  resolve imports against it without involving the host build system.

Probably **A + B**: A for the common case, B as the lowest-common-denominator
escape hatch.

---

## 4. Cross-cutting concerns

- **Generics & monomorphization across package boundaries.** If module
  `foo` defines `Sampler<T>` and module `bar` instantiates it with its own
  type, who is responsible for monomorphization? This affects whether
  pre-built artifacts are useful at all.
- **Link-time specialization.** Slang's specialization happens late; the
  registry should not assume an artifact is the final compile result.
- **Reproducibility.** Lockfile + content digests + pinned compiler version.
- **Offline / vendor mode.** `slangpm vendor` copies everything into the
  consumer's tree; useful for game-studio environments without registry
  access.
- **Private registries.** Mirror-of-public + private overlay (Cargo's
  `[source.crates-io] replace-with = …` pattern).

---

## 5. Decision ledger

| Dimension                           | Options on the table        | Must decide before code | Deferred until            |
| ----------------------------------- | --------------------------- | ----------------------- | ------------------------- |
| 3.1 Identity & versioning           | flat / scoped / URL + semver | **yes**                | —                         |
| 3.2 Manifest format & fields        | TOML / JSON / Slang-native  | **yes**                | —                         |
| 3.3 Source vs. precompiled          | source / artifact / hybrid  | **yes**                | —                         |
| 3.4 Compiler / target / cap matrix  | sparse / ranges / on-demand | no                      | after 3.3                 |
| 3.5 Resolver + lockfile             | MVS / SAT / PubGrub         | no                      | after 3.1 + 3.2           |
| 3.6 Registry architecture           | git / API / CDN / OCI       | **yes**                | —                         |
| 3.7 Publishing & auth               | tokens / org / Sigstore     | no                      | after 3.6                 |
| 3.8 CLI surface                     | command list                | no                      | after 3.2 + 3.5           |
| 3.9 Security & trust                | signing / no-build-scripts  | no                      | after 3.6 + 3.7           |
| 3.10 Host build integration         | cmake / json / compiler     | no, but v1-blocking     | after 3.2 + 3.5           |

---

## 6. Walkthrough vignettes

These exercise the sketch end-to-end. Where the sketch is under-specified,
note it.

### 6.1 Publish a BRDF library

Alice maintains a `disney-brdf` Slang module. She writes a manifest:

```toml
name              = "disney-brdf"
version           = "0.3.0"
module            = "DisneyBRDF"
slang.min_version = ">=2025.2"
targets           = ["hlsl", "spirv", "metal", "wgsl"]
capabilities      = []          # pure shading math, no special caps
exports.interfaces = ["IBRDF"]
```

She runs `slangpm publish`. The CLI compiles against the declared targets
to validate, hashes the source tree, and uploads `(manifest, source
tarball, signature)` to the index. The index is a git repo; her token gives
her commit access to the `disney-brdf/` namespace.

> **Gap surfaced:** what does "validate against the declared targets" mean
> if the manifest declares only ranges (3.4 option B)? Probably: compile
> against the *minimum* declared compiler version for each target.

### 6.2 Consume from a Vulkan engine

Bob's engine has a `slangpm.toml`:

```toml
name              = "my-engine-shaders"
version           = "0.0.0"
slang.min_version = ">=2025.2"
targets           = ["spirv"]
capabilities      = ["sm_6_5"]
dependencies      = { "disney-brdf" = "^0.3", "envmap-sampling" = "^1.1" }
```

`slangpm install` resolves, writes `slangpm.lock`, and materializes sources
into `.slang-deps/`. `slangpm export --format=cmake` emits
`slang-deps.cmake` adding include directories so `import DisneyBRDF;`
resolves. The engine's CMake includes this file and links a `Slang::deps`
INTERFACE target.

> **Gap surfaced:** capability intersection — if `disney-brdf` declares
> `capabilities = []` and the consumer declares `["sm_6_5"]`, the union is
> `["sm_6_5"]`. Easy. Harder case: `envmap-sampling` declares
> `["wave_ops"]` and the consumer's `targets = ["wgsl"]`, which doesn't
> support wave ops. Resolver must error with a clear message.

### 6.3 Pin across a Slang compiler upgrade

Bob upgrades from Slang 2025.2 to 2026.1. The lockfile still pins
`disney-brdf 0.3.0`, but that version's manifest says
`slang.max_version = "<2026.0"`. `slangpm install` errors and points Bob at
`slangpm update disney-brdf`, which finds `disney-brdf 0.4.0` declaring
`slang.min_version = ">=2026.0"`, updates the lockfile, and proceeds.

> **Gap surfaced:** what if no compatible version exists? The CLI should
> say *exactly* which transitive dep blocks the upgrade. PubGrub's
> error-reporting strengths argue for option C in 3.5.

---

## 7. Appendix — illustrative formats

These are sketches, not normative.

### 7.1 Example manifest (TOML)

```toml
name              = "envmap-sampling"
version           = "1.1.2"
module            = "EnvmapSampling"
description       = "Importance-sampled environment maps for Slang."
license           = "MIT"
authors           = ["Alice <a@example.com>"]
repository        = "https://github.com/example/envmap-sampling"

slang.min_version = ">=2025.2"
slang.max_version = "<2027.0"
targets           = ["hlsl", "spirv", "metal", "wgsl"]
capabilities      = []

exports.interfaces = ["IEnvmapSampler"]

[dependencies]
disney-brdf = "^0.3"

[features]
multiscatter = []
```

### 7.2 Example index entry (JSON, git-backed index)

```json
{
  "name": "envmap-sampling",
  "vers": "1.1.2",
  "deps": [
    { "name": "disney-brdf", "req": "^0.3", "kind": "normal" }
  ],
  "cksum": "sha256:0d2c…",
  "slang": { "min": "2025.2", "max": "<2027.0" },
  "targets": ["hlsl", "spirv", "metal", "wgsl"],
  "capabilities": [],
  "yanked": false
}
```

### 7.3 Example lockfile

```toml
version = 1

[[package]]
name    = "envmap-sampling"
version = "1.1.2"
source  = "registry+https://slangpkg.dev/index"
digest  = "sha256:0d2c…"

[[package]]
name    = "disney-brdf"
version = "0.3.4"
source  = "registry+https://slangpkg.dev/index"
digest  = "sha256:91af…"

[meta]
slang_version = "2025.3"
```

---

## 8. What's next

Decide the four `MUST-DECIDE-NOW` rows in the ledger (3.1, 3.2, 3.3, 3.6).
Once those are locked, fork this document into:

- `manifest-spec.md` — normative schema and validation rules.
- `registry-protocol.md` — index layout, publish flow, auth.
- `resolver-semantics.md` — algorithm, error model, lockfile format.
- `cli-ux.md` — command-by-command reference.
