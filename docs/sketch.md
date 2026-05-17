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
- Targets are plural: HLSL, DXIL, SPIR-V, GLSL, Metal, WGSL, CUDA, C++.
  Some modules are target-agnostic; some are not.
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
- **Target** — a compilation backend. The shader-language targets a
  package manifest will typically declare are `hlsl`, `dxil`, `spirv`,
  `glsl`, `metal`, `wgsl`, `cuda`, and `cpp`. `slangc` supports additional
  output forms (`metallib`, `host-cpp`, `torch`, …) that are out of scope
  for v0 manifests.
- **Capability** — a Slang-declared requirement (e.g. `_sm_6_5`,
  `raytracing`, `mesh`, `subgroup_basic`). Atom names and the implication
  lattice are defined in `slang-capabilities.capdef`.
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

**Slang wrinkle.** Slang's import surface admits two flavors: identifier-form
(`import foo;`) and string-form (`import "@ns/foo";`). Empirically the
linker keys module identity on the full string, so a scoped name like
`@nvidia/math` is a real identity rather than file-naming sugar (see
`experiments/module-name-identity/`). Public API surface includes
generics, interfaces, and associated types — small textual changes can
be ABI-breaking even when they look additive.

**Options.**

- **A. Flat name + semver.** `gbuffer-utils 0.4.1`. Easiest; collides on
  popular names.
- **B. Scoped name + semver.** `@nvidia/raytracing-utils 0.4.1`. Mirrors
  npm/Cargo conventions; cheap namespace ownership.
- **C. URL-as-name (Go-style) + semver.** `github.com/org/repo 0.4.1`.
  Decentralized; no central name registry needed; awkward for users.
- **D. Hybrid: semver in manifest, content digest in lockfile.** Layer on
  top of A/B/C. Probably required regardless of which name scheme wins.

**Decision (naming): B, used at every layer.** The registry-published
identifier is a scoped name (`@org/pkg`), and the same string is the
Slang module identity verbatim:

```toml
# manifest
name = "@nvidia/math"
```

```slang
// primary file
module "@nvidia/math";
```

```slang
// consumer
import "@nvidia/math";
```

No separate "registry name → Slang module name" mapping. Provenance is
visible at every call site, and packages from different scopes can never
collide on identity by construction.

Flat unscoped module names remain *permitted* (a single-author package
can still declare `module foo_bar;` and `import foo_bar;`), but the
registry guarantees uniqueness only within the scoped namespace —
collisions on unscoped names are the author's problem.

Option C is rejected: the experiment showed Slang would accept
URL-shaped string imports too, but they're structurally identical to B
with a hostname tax that couples identity to a hoster for no extra
benefit. Option D layers on top of B unchanged.

**Decision (versioning): mechanical Elm-style publish-time enforcement,
with the digest spec deferred.** Grounded empirically in
`experiments/semver-break-catalog/` (29 mutation cases probed against
a fixed downstream consumer, plus a probe of existing slangc artifacts
as digest candidates).

For semver semantics, the catalogue gives a first-cut classification
of mutations to a Slang module's public surface (scoped to the
catalogue's consumer access patterns — see the experiment README's
Limitations section):

- **Breaking by signature.** Function or method rename; required
  parameter add; parameter remove; type or field rename or remove;
  visibility demotion (public → internal); conformance removal;
  interface method add without a default implementation; associated
  type add (Slang has no observed default-binding mechanism for
  associated types); generic constraint tightening.
- **Breaking by capability.** Switching a `[require]` declaration
  to an atom that conflicts with one the original transitively
  implied, within a mutually-exclusive atom group (target group:
  `spirv` ↔ `hlsl` ↔ `metal` ↔ …; stage group: `vertex` ↔
  `fragment` ↔ `compute` ↔ …).
- **Conditionally additive.** Field add, field reorder, overload
  add, interface method add *with* a default, new conformance for a
  new type, parameter or generic-parameter rename, narrowing along
  a capability-implication chain (e.g. `spirv_1_3` → `spirv_1_0`),
  removing a `[require]` entirely. These passed under the
  catalogue's consumer; some flip under different consumer access
  patterns (positional struct init, dynamic dispatch through an
  interface-typed value, keyword arguments).
- **Implicit conversions.** Slang accepts `int`↔`float` coercions
  with a warning or silently at function returns, struct fields,
  method returns, and parameters. The compiler tolerates these; the
  digest should treat them as breaking anyway, since the
  publisher's intent is a type change.

For enforcement, `slangpm publish` (or its equivalent) refuses a
minor bump that crosses the digest boundary. The check **compiles
the library**, not just diffs its surface — interface-conformance
cascades like `add-method-no-default` produce errors inside the
library itself, which a pure-surface diff would miss.

The digest itself is deferred to a follow-up spec
(`sig-digest-spec.md`, see §8). The catalogue gives concrete
acceptance criteria: combine the binary `.slang-module`'s
capability awareness with text-form filtering (`-dump-module` strips
`[require]` annotations), strip identifier-rename noise (parameter
names, generic-parameter names, internal symbols are not part of
the consumer-observable ABI per the catalogue), and treat the
int↔float-style implicit-conversion cases as breaking. No existing
slangc artifact is sufficient on its own.

**Open question** (versioning sub-decision, still unresolved).

- Pre-1.0 rules (Cargo treats `0.x.y` minor as breaking; npm doesn't).
  Not driven by any Slang-specific fact — a values choice.

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

# Slang capability requirements, in disjunction-of-conjunctions form.
# Atom names are Slang's own (see shader-slang/slang docs/user-guide/05-capabilities.md);
# each inner list is AND'd, outer list is OR'd. Mirrors the shape of multiple
# `[require(...)]` attributes on a Slang function.
capabilities      = [
  ["hlsl", "_sm_6_5"],
  ["spirv_1_4", "SPV_KHR_ray_tracing"],
]

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

**Slang wrinkle.** Capability satisfaction is not the registry's job. Slang
itself enforces `[require(...)]` declarations at type-check time, with an
implication lattice that handles subsumption automatically (`_sm_6_5` implies
`_sm_6_0`, `spvShaderClockKHR` implies `SPV_KHR_shader_clock` implies
`spirv_1_0`, etc.) and a DNF normal form across multiple `[require]`
attributes on a function. The registry's role is narrower: surface the
**author-declared capability DNF** in the index so the resolver can fail
fast on obvious mismatches before `slangc` is even invoked. Don't
re-implement Slang's satisfaction logic in the resolver.

**Options.**

- **A. Surface the declared DNF as-is.** Index entry stores the same
  disjunction-of-conjunctions the manifest declared. Resolver checks that
  at least one clause is target-compatible with the consumer; final
  satisfaction is `slangc`'s problem. Cheapest; matches Slang's model.
- **B. Expand to explicit (compiler, target, caps) tuples.** Pre-compute
  every supported profile and store the cross-product. Precise but verbose
  and brittle across compiler releases.
- **C. Build-on-demand.** Build farm produces artifacts per requested
  profile. Heavyweight; presupposes artifact-canonical distribution (3.3);
  defer indefinitely.

**Tag.** Deferred until 3.3 lands. If 3.3 = source-only or source-canonical,
option A is the obvious choice — Slang already does the hard work.

---

### 3.5 Dependency resolution & lockfile &nbsp;&nbsp; `DEFER`

**Problem.** Given a root manifest, produce a concrete, reproducible set of
package versions.

**Slang wrinkle.** One extra axis flows through the graph: required Slang
compiler version (intersect across the graph). Capability requirements
*don't* need to be combined by the resolver — Slang's own `[require]`
type-checking (3.4) handles cross-module satisfaction. The resolver only
needs to verify, per package, that at least one declared DNF clause is
target-compatible with the consumer's profile.

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
| 3.1 Identity & versioning           | naming: scoped at every layer (decided); semver semantics: mechanical Elm-style enforcement (decided, digest spec deferred); pre-1.0 rule: open | naming + enforcement: done; pre-1.0 rule: no | — |
| 3.2 Manifest format & fields        | TOML / JSON / Slang-native  | **yes**                | —                         |
| 3.3 Source vs. precompiled          | source / artifact / hybrid  | **yes**                | —                         |
| 3.4 Compiler / target / cap matrix  | surface declared DNF / expand to explicit matrix | no | after 3.3 |
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
> if the manifest declares only a DNF (3.4 option A) rather than an explicit
> matrix? Probably: compile one canonical clause per declared target against
> the *minimum* declared compiler version.

### 6.2 Consume from a Vulkan engine

Bob's engine has a `slangpm.toml`:

```toml
name              = "my-engine-shaders"
version           = "0.0.0"
slang.min_version = ">=2025.2"
targets           = ["spirv"]
capabilities      = [["spirv_1_4", "_sm_6_5"]]
dependencies      = { "disney-brdf" = "^0.3", "envmap-sampling" = "^1.1" }
```

`slangpm install` resolves, writes `slangpm.lock`, and materializes sources
into `.slang-deps/`. `slangpm export --format=cmake` emits
`slang-deps.cmake` adding include directories so `import DisneyBRDF;`
resolves. The engine's CMake includes this file and links a `Slang::deps`
INTERFACE target.

> **Gap surfaced:** capability gating, not intersection. A package with no
> declared `capabilities` is capability-neutral — its public symbols carry
> their own `[require]` declarations and `slangc` checks them at compile
> time. The resolver's job is to verify that *at least one* clause of each
> dependency's declared DNF is compatible with the consumer's target/profile
> set. Example: `envmap-sampling` declares
> `[["hlsl", "_sm_6_5", "waveops"], ["spirv_1_4", "waveops"]]` and the
> consumer's `targets = ["wgsl"]`. No clause is wgsl-compatible — resolver
> rejects with a message naming the package, the consumer's target, and
> the (target-incompatible) declared clauses. Final per-call-site
> satisfaction is still slangc's responsibility.

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
capabilities      = [
  ["hlsl", "_sm_6_2"],
  ["spirv_1_3"],
  ["metal"],
  ["wgsl"],
]

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
  "capabilities": [
    ["hlsl", "_sm_6_2"],
    ["spirv_1_3"],
    ["metal"],
    ["wgsl"]
  ],
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

Decide the remaining `MUST-DECIDE-NOW` rows in the ledger (3.2, 3.3,
3.6) and the pre-1.0 rule still open in 3.1. Once those are locked,
fork this document into:

- `manifest-spec.md` — normative schema and validation rules.
- `registry-protocol.md` — index layout, publish flow, auth.
- `resolver-semantics.md` — algorithm, error model, lockfile format.
- `cli-ux.md` — command-by-command reference.
- `sig-digest-spec.md` — canonicalisation rules for the publish-time
  semver-enforcement digest (3.1 decision; acceptance criteria in
  `experiments/semver-break-catalog/`).
