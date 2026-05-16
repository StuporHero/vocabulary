# Semver-break catalogue

## Question

`docs/sketch.md` decision 3.1 says naming is settled but versioning is
not. The versioning sub-question is: **what counts as a breaking change
for a Slang module**, and whether tooling can enforce that
classification at publish time (the way Elm's package manager does for
Elm).

The catalogue answers the empirical half for a **representative
subset** of public-API mutations: does a downstream consumer that was
compiling cleanly still compile against the mutated library? Reasoning
is replaced with measurement. See the "Limitations" section below for
what the catalogue does *not* cover.

The probe addresses the secondary question — do any existing
slangc-emitted artifacts (`-dump-module` text, the binary
`.slang-module` file) already constitute a usable signature digest?

## Slangc version

`v2026.8.1`, Linux x86_64 prebuilt from the official GitHub release.
Pinned in both `run.sh` and `probe-dump-module.sh`.

## Method

A baseline library (`baseline/lib.slang`) declares a representative
public surface: a function, a generic function, a struct with named
fields, an interface with one method, a type conforming to that
interface, and a generic function constrained on the interface. A
fixed consumer (`consumer.slang`) calls each piece.

Each case under `cases/<category>/<name>/` contains a `lib.slang` that
differs from the baseline by one mutation, plus an `EXPECTED` file
recording the predicted outcome (`passes` or `breaks`). The runner
stages each case at `<tmp>/@org/lib.slang`, compiles the consumer
against it, and records the actual outcome side-by-side with the
prediction. Capability cases bring their own consumer because they
need a `[require]`-gated call site.

**Compilation scope.** Every case compiles to `-target spirv -stage
compute` under slangc's default profile. Capability findings in
particular are defined by the target; a glsl- or hlsl-bound consumer
might flip individual outcomes. Read all "within-family /
cross-family" claims as scoped to a spirv-compute consumer.

Re-run with `bash experiments/semver-break-catalog/run.sh` and
`bash experiments/semver-break-catalog/probe-dump-module.sh`.

## Findings — surface mutations

### Functions (`fecf74a`)

| case | expected | actual |
| ---- | -------- | ------ |
| rename                     | breaks | breaks |
| add-param                  | breaks | breaks |
| add-param-default          | passes | passes |
| remove-param               | breaks | breaks |
| change-return-type (int→float) | breaks | **passes** (with warning) |
| change-param-type (int→float)  | passes | passes |
| rename-param               | passes | passes |
| add-overload               | passes | passes |
| add-generic-constraint     | breaks | breaks |
| rename-generic-param       | passes | passes |

Surprise: changing the return type from `int` to `float` *passes* with
`warning[E30081]: implicit conversion not recommended` rather than
failing. Parameter names and generic-parameter names are not part of
the ABI as far as slangc cares — renames in either are invisible to
the consumer.

### Types (`68a01d4`)

| case | expected | actual |
| ---- | -------- | ------ |
| rename-field                  | breaks | breaks |
| add-field                     | passes | passes |
| remove-field                  | breaks | breaks |
| reorder-fields                | passes | passes |
| change-field-type (int→float) | passes | passes |
| field-public-to-internal      | breaks | breaks |
| type-public-to-internal       | breaks | breaks |

All seven predictions held. Visibility demotions trigger
`error[E30600]: declaration not accessible`. Reordering fields is
source-compatible (consumer uses named access); buffer layout
obviously changes, which is a separate ABI question outside source
semver. The int→float field change passes silently (no warning),
mirroring the function-level finding.

### Interfaces + conformances (`ac6c146`)

| case | expected | actual |
| ---- | -------- | ------ |
| add-method-with-default       | passes | passes |
| add-method-no-default         | breaks | breaks |
| rename-method                 | breaks | breaks |
| add-associated-type           | breaks | breaks |
| change-method-return-type     | passes | passes |
| remove-conformance            | breaks | breaks |
| add-conformance-elsewhere     | passes | passes |

The most consequential finding: **adding an interface method with a
default implementation is non-breaking**. Conforming types don't need
to override; the library compiles and the consumer is unaffected.
Slang's interface evolution story is genuinely friendly to
minor-version additions.

Adding a method *without* a default, or adding an associated type
without one, breaks differently: the library itself fails to compile
because the existing conforming type doesn't satisfy the new
requirement. The consumer's `import` then fails with
`error[E39999]: import failed due to compilation error`. A publish-
time tool has to compile the library, not just diff its surface, to
catch this.

Adding a new conformance for an entirely new type
(`add-conformance-elsewhere`) is non-breaking — Slang's overload
resolution doesn't pick up ambiguity from types the consumer never
references.

## Findings — capability mutations (`ae44dab`, with `widen-spirv-version` dropped in `ab5cbbc`)

| case | expected | actual |
| ---- | -------- | ------ |
| baseline-control     | passes | passes |
| remove-require       | passes | passes |
| narrow-require       | passes | passes |
| cross-target-require | breaks | breaks |

(A fifth case, `widen-spirv-version`, was removed during methodology
review: its EXPECTED was authored without a clear a-priori prediction
— the lib.slang comment said "outcome depends ... recording the
empirical answer" — so it didn't count as a real test.)

Within-family adjustments (removing the `[require]`, narrowing from
`spirv_1_3` to `spirv_1_0`) are non-breaking for the spirv-compute
consumer under slangc's default profile. The catalogue does **not**
cover widening within the same family or cross-target widening to a
family the consumer's target already implies; either case might
behave differently.

Switching to a different target family (`spirv_1_3` → `hlsl + _sm_6_5`)
breaks the spirv consumer with a precise diagnostic:

```
error[E36107]: unavailable features in entry point
 --> consumer.slang:5:6
  | void main(uint3 tid : SV_DispatchThreadID)
  |      ^^^^ entrypoint 'main' uses features that are not available
  |           in 'compute' stage for 'spirv' compilation target.
note: see using of 'needs_caps' ...
note: see definition of 'needs_caps' ...
```

The diagnostic chain (entry point → call site → declaration) is
exactly the structure a publish-time tool would want.

## Findings — secondary probe (`28f948f`)

Two candidate existing digest sources tested against the 29 cases:

|                       | ok | ok-err | OVER | MISS |
| --------------------- | -- | ------ | ---- | ---- |
| `-dump-module` (text) | 14 | 3      | 11   | **1** |
| `.slang-module` (bin) | 13 | 3      | 13   | 0    |

`MISS` is the dangerous outcome — a digest that's "same" when the
consumer actually breaks would let a major change slip through as a
minor bump. The text dump misses one case in the catalogue:
`capabilities/cross-target-require`. Verified manually: the dump for
`[require(spirv_1_3)]` is byte-identical to the dump for
`[require(hlsl, _sm_6_5)]`. The text disassembly strips capability
annotations entirely.

The binary `.slang-module` produces no false negatives in this
catalogue. That's encouraging but not "sound": the sample is small
enough that a wider catalogue could surface MISSes. Of the 15
passing cases, it over-reports on 13 (an 87% over-rate), including
invisible mutations like parameter renames.

`OVER` is not "just nuisance" the way the original legend implied.
For a publish-time tool, OVER means the digest demands a major bump
for a change that doesn't break consumers. At an 87% over-rate
(13 of 15 passing cases for the binary; 11 of 15 for the text dump
— 73%), authors would routinely be told "you need a major" for
genuinely backwards-compatible patches, which trains them to override
the tool, defeating the point of mechanical enforcement. (Elm gets
away with its strict regime because its detection is precise; a tool
with this OVER rate would not.)

So no existing slangc artifact is sufficient on its own:

- **Dump-module text** is selective but unsound (capability-blind).
- **Binary slang-module** is no-MISS-in-this-sample but loose.

A real digest would need to combine the binary's capability awareness
with the text form's filtering, plus extra canonicalization to drop
the things the catalogue showed are invisible (parameter names,
generic parameter names, internal symbols). That's nontrivial work,
but it's a *defined* nontrivial work, not an unknown.

Also noted: the binary `.slang-module` embeds the absolute path of
the source file. The probe stages each source as a canonical filename
before compiling; any production tool that hashes the binary would
need the same workaround (or a strip-path post-process).

## Synthesis: what the catalogue tells us about the semver question

1. **Slang's diagnostics carry enough information to support an
   Elm-style check; the digest mechanism remains the open problem.**
   Mutations in the catalogue produce sharp, well-targeted error
   messages — the necessary condition for a publish-time enforcement
   tool is met. The sufficient condition (a stable, selective digest
   that classifies deltas) is not. The probe shows that neither
   existing slangc artifact is the digest by itself.

2. **The catalogue suggests three first-cut categories** for what a
   digest needs to distinguish (scoped to the access patterns the
   consumer actually exercises — see Limitations):

   - **Breaking by signature** — function/method rename, required
     parameter add, remove, type/field rename or remove, visibility
     demotion, conformance removal, interface method add without
     default, associated type add without default, generic constraint
     tightening.
   - **Breaking by capability** — cross-target-family switch in a
     `[require]` declaration.
   - **Conditionally additive** — add field, reorder fields, add
     overload, add interface method *with* default, add conformance
     for a new type, parameter/generic-param rename, within-family
     `[require]` narrowing/removal. These passed under the catalogue's
     consumer; some are conditionally safe under specific access
     patterns (e.g. add-field and reorder-fields rely on named field
     access — a positional-init consumer would flip both).

   A note rather than a fourth category: Slang accepts some `int`↔`float`
   mismatches as implicit conversions (silently or with a warning) —
   `change-return-type`, `change-method-return-type`, `change-param-type`,
   `change-field-type`. Three of those passed; one warned. That's
   evidence of an implicit-conversion rule, not a structurally
   distinct kind of break. For digest purposes, treat type changes as
   breaking.

3. **The digest mechanism is not a single slangc artifact today.**
   Building it means combining the IR (for structural surface),
   per-symbol capability DNF extraction, and a canonicalization pass
   that strips identifiers that the catalogue showed are invisible.
   This is the spec-deferral the sketch already calls for, but now
   the catalogue gives concrete acceptance criteria for it.

4. **Publish-time tooling must compile the library, not just diff
   surfaces.** Cases like `interfaces/add-method-no-default` produce
   their primary error *inside* the library (the conforming type no
   longer satisfies the interface). A surface-only diff would miss
   this; a full compile catches it. This is the cleanest claim in the
   synthesis.

## Limitations

The catalogue is exploratory, not exhaustive. Read its claims as
"these mutations did or didn't break this consumer under this
compilation target," not as a general semver classification.

- **Single consumer pattern.** The consumer uses one access shape per
  surface element: one generic call, one struct field write (named,
  not positional), one method call. It does **not** exercise
  existential dispatch on `IShape` (`IShape s = sq; s.area()`),
  positional struct init (`Point{4,5}`), `inout`/`out` parameters,
  aliased types, `extension`-defined methods, or generic constraints
  binding multiple interfaces. Some catalogue "passes" verdicts are
  conditional on the consumer's access pattern — adding or reordering
  struct fields would likely flip to "breaks" under a positional-init
  consumer.

- **Single compilation target.** All cases compile to `-target spirv
  -stage compute`. The capability findings depend on the default
  spirv profile; a glsl, hlsl, or metal consumer might flip the
  within-family vs cross-family classification.

- **Mutation gaps.** Categories arguably belonging in a full
  "what's breaking?" study but not exercised here: `inout`/`out`
  parameter mutability, free-function ↔ method moves, `extension`
  add/remove, operator overloads (`__init`, `operator+`),
  `enum` cases (add/remove/reorder), attributes other than `[require]`
  (`[mutating]`, `[ForceInline]`), removing an overload from a set
  the consumer relies on, default values for generic type-args,
  interface-inheritance changes, visibility tightening on generics
  or interfaces.

- **Sample size.** 29 cases — 14 breaks (3 ok-err + 11 surface),
  15 passes — is enough to find direction and to surface a definite
  MISS in the text-dump digest. It is not enough to claim bounds on
  the binary's miss rate; the breaking-case denominator is small
  enough that "no misses observed" should not be read as "sound." The
  passing-case denominator (15) is better-evidenced and supports the
  high OVER-rate conclusion more firmly.

## Re-running

```
bash experiments/semver-break-catalog/run.sh
bash experiments/semver-break-catalog/probe-dump-module.sh
```

Both are idempotent. `run.sh` writes to `results.txt`;
`probe-dump-module.sh` writes to `probe-dump-module.txt`. Re-runs are
byte-identical aside from the `Date` line — `run.sh` strips per-run
`mktemp` paths and the experiment's absolute prefix from captured
diagnostics. The slangc binary is downloaded once into the gitignored
`experiments/.slang-bin/`.

## Suggested next experiments

The methodology review surfaced three follow-ups that would
strengthen the catalogue's claims rather than merely extend them:

1. **Second consumer.** Add a consumer that uses existential
   dispatch on `IShape`, positional struct init, and `inout`/`out`
   parameters. Re-run the catalogue against both. The matrix will
   distinguish "unconditionally non-breaking" from "non-breaking
   under this access pattern" — and likely flip several catalogue
   "passes" to conditional verdicts.

2. **Prototype the digest.** Build a canonicalised signature from
   `-dump-module` text plus per-symbol capability DNF extraction, and
   re-run the probe. That tests the synthesis's load-bearing claim
   ("the hard part is defining the digest precisely") rather than
   asserting it.

3. **Multi-target sweep on capabilities.** Re-run the capability
   cases under at least one additional `-target` (glsl or hlsl),
   since the within-family / cross-family taxonomy is defined by the
   target.
