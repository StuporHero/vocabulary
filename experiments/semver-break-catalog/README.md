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
slangc-emitted artifacts (`-dump-module`'s IR disassembly, the
raw `.slang-module` binary serialisation) already constitute a
usable signature digest?

## Slangc version

`v2026.8.1`, Linux x86_64 prebuilt from the official GitHub release.
Pinned in both `run.sh` and `probe-dump-module.sh`.

## Method

A baseline library (`baseline/lib.slang`) declares a **minimal public
surface** covering function/generic/struct/interface/conformance: a
function, a generic function, a struct with named fields, an
interface with one method, a type conforming to that interface, and a
generic function constrained on the interface. It does **not** cover
enums, extensions, operator overloads / `__init`, nested namespaces,
resource-typed parameters, or `inout`/`out`. A fixed consumer
(`consumer.slang`) calls each piece via concrete-type dispatch (not
through an interface-typed value with dynamic dispatch).

Each case under `cases/<category>/<name>/` contains a `lib.slang` that
differs from the baseline by one mutation, plus an `EXPECTED` file
recording the predicted outcome (`passes` or `breaks`). The runner
stages each case at `<tmp>/@org/lib.slang`, compiles the consumer
against it, and records the actual outcome side-by-side with the
prediction. Capability cases bring their own consumer because they
need a `[require]`-gated call site.

**Compilation scope.** Every case compiles with `-target spirv
-stage compute -entry main` and no explicit `-profile` flag.
Capability findings in particular are defined by the target; a
glsl- or hlsl-bound consumer might flip individual outcomes. Slang's
capability docs (`user-guide/05-capabilities.md`) describe
mutually-exclusive capability groups — target atoms
(`hlsl`, `glsl`, `spirv`, `metal`, `wgsl`, `cuda`, `cpp`) are one
such group; stage atoms (`vertex`, `fragment`, `compute`, …) are
another. The catalogue's capability findings are scoped to a
spirv-compute consumer.

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
default implementation is non-breaking** under the catalogue's
conditions. Conforming types fall back to the default; the library
compiles and the consumer is unaffected. The user-guide flags one
wrinkle this catalogue doesn't exercise: if a conforming type already
has a method with the same name and signature, that type now needs
an explicit `override` keyword to disambiguate
(`user-guide/06-interfaces-generics.md` lines 49-70). Within
that constraint, default-method additions are a real affordance for
non-major bumps.

Adding a method *without* a default breaks differently: the library
itself fails to compile because the existing conforming type doesn't
satisfy the new requirement. Adding an associated type behaves the
same way — Slang has no associated-type analogue of method defaults,
so every conforming type must provide a binding. The consumer's
`import` then fails with `error[E39999]: import failed due to
compilation error`. A publish-time tool has to compile the library,
not just diff its surface, to catch this.

`change-method-return-type` is not an independent data point: the
consumer calls `sq1.area()` directly on the concrete `Square`, so the
int-from-float conversion goes through the same implicit-coercion
path that `functions/change-return-type` already exercised. A
consumer that dispatched via an interface-typed value (`IShape s = sq1;
s.area()`) might or might not behave the same way — that's untested.

(Interface-member visibility isn't catalogued either. Slang's rule
is that interface members inherit visibility from the parent
interface — `user-guide/04-modules-and-access-control.md` L185 — so
`public→internal` demotion on an interface method isn't a separate
mutation shape from demoting the whole interface, which we cover.)

Adding a new conformance for an entirely new type
(`add-conformance-elsewhere`) is non-breaking — Slang's name
resolution and generic specialization at sites that don't mention
the new type aren't perturbed by its existence. (Overload resolution
isn't really the relevant mechanism here: nothing in the consumer
calls into two ambiguous candidates. The claim is narrower than that:
adding a new type and its conformance leaves untouched code
untouched.)

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

Removing the `[require]` and narrowing to an atom that the original
implies (`spirv_1_3` → `spirv_1_0`; per `user-guide/05-capabilities.md`
lines 44-54, a Slang capability can imply other capabilities, and the
checker expands all implications) are non-breaking for the
spirv-compute consumer with no explicit `-profile` flag. The catalogue
does **not** cover the opposite direction (widening to a strictly
larger implication) or adding a requirement whose atoms the consumer
already satisfies; either could behave differently.

Switching to a conflicting target atom (`spirv_1_3` → `hlsl + sm_6_5`,
across the target mutually-exclusive group) breaks the spirv consumer
with a precise diagnostic:

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

## Findings — secondary probe (`28f948f`, classification fixed in `4474455`)

Two candidate existing digest sources tested against the 29 cases.
The probe classifies digest verdicts against each case's ACTUAL
(empirical) outcome, not its a-priori EXPECTED label.

|                              | ok | ok-err | OVER | MISS |
| ---------------------------- | -- | ------ | ---- | ---- |
| `-dump-module` (disassembly) | 13 | 3      | 12   | **1** |
| `.slang-module` (raw IR)     | 12 | 3      | 14   | 0    |

Both digest sources are hashes of the same module IR: the
disassembly is the IR printed as text via slangc's `-dump-module`,
which omits some annotations (notably capability requirements); the
raw form is the on-disk binary serialisation. The differences in the
table below are properties of what each form *includes* in its
output, not "text vs binary" in any deeper sense.

`MISS` is the dangerous outcome — a digest that's "same" when the
consumer actually breaks would let a major change slip through as a
minor bump. The disassembly misses one case in the catalogue:
`capabilities/cross-target-require`. Verified manually: the
disassembly for `[require(spirv_1_3)]` is byte-identical to the one
for `[require(hlsl, sm_6_5)]`. `-dump-module` doesn't print capability
annotations at all.

The binary `.slang-module` produces no false negatives in this
catalogue. That's encouraging but not "sound": the sample is small
enough that a wider catalogue could surface MISSes.

**Excluding the two identity controls** (`baseline/control` and
`capabilities/baseline-control`, which are not mutations), there are
14 real-mutation cases with ACTUAL=passes. The binary OVERs on all
of them (14/14); the text dump OVERs on 12/14. With a denominator
this small, a single misclassification would shift these by ~7
points — the fractions are reported as fractions, not percentages,
for that reason. Including the controls in the denominator (16
total) gives 14/16 and 12/16 respectively, but the controls aren't
contributing evidence about over-reporting either way.

`OVER` is not "just nuisance" the way the original legend implied.
For a publish-time tool, OVER means the digest demands a major bump
for a change that doesn't break consumers, training authors to
override the tool and defeating the point of mechanical enforcement.

There is a real tension here, though: several of the OVER cases are
int↔float type changes (`change-return-type`, `change-method-return-type`,
`change-param-type`, `change-field-type`) that slangc accepts via
implicit conversion. The catalogue records "passes" because the
compiler accepts; the digest flags "diff" because the source
genuinely changed. **For a publish-time tool that treats type
changes as breaking** (which the synthesis recommends), the digest
flagging these is *desired* behavior, not OVER. The probe measures
"digest vs. source-compatibility check"; a digest tuned for "semver
intent" rather than "source compatibility" would correctly bump these
to "breaks" and the OVER rate would drop. The high OVER rate against
strict source-compat thus understates the digest's usefulness for an
intent-based enforcement tool — but it remains an honest measurement
of the gap between the two definitions.

So no existing slangc artifact is sufficient on its own:

- **Dump-module text** is selective but unsound (capability-blind).
- **Binary slang-module** is no-MISS-in-this-sample but loose.

A real digest would need to combine the binary's capability awareness
with the text form's filtering, plus extra canonicalization to drop
the things the catalogue showed are invisible (parameter names,
generic parameter names, internal symbols). That's a tractable next
step, conditional on a wider catalogue not surfacing further blind
spots that change the requirements.

Also noted: the binary `.slang-module` embeds the absolute path of
the source file. The probe stages each source as a canonical filename
before compiling; any production tool that hashes the binary would
need the same workaround (or a strip-path post-process).

**Precompile invocation.** The probe precompiles each case via
`slangc -emit-ir <lib.slang>`. A real publish-time tool might use
different flags (e.g. an explicit `-O0`, target-specific options,
or `-stage`-agnostic builds), and digest stability under those
invocations is not tested here.

## Synthesis: what the catalogue tells us about the semver question

1. **Slang's diagnostics carry enough information to support an
   Elm-style check for the mutation shapes tested; the digest
   mechanism remains the open problem.** Mutations in the catalogue
   produce sharp, well-targeted error messages — the necessary
   condition for a publish-time enforcement tool appears met for the
   mutation shapes tested. The sufficient condition (a stable,
   selective digest that classifies deltas) is not. The probe shows
   that neither existing slangc artifact is the digest by itself.
   The omitted mutation categories (see Limitations) could in
   principle change either conclusion.

2. **The catalogue suggests three first-cut categories** for what a
   digest needs to distinguish (scoped to the access patterns the
   consumer actually exercises — see Limitations):

   - **Breaking by signature** — function/method rename, required
     parameter add, remove, type/field rename or remove, visibility
     demotion, conformance removal, interface method add without
     default, associated-type add (associated types have no
     default-binding equivalent of method defaults), generic
     constraint tightening.
   - **Breaking by capability** — switching to a conflicting atom in
     a mutually-exclusive group (e.g. spirv → hlsl in the target
     group) inside a `[require]` declaration.
   - **Conditionally additive** — add field, reorder fields, add
     overload, add interface method *with* default, add conformance
     for a new type, parameter/generic-param rename, narrowing to an
     atom that the original implies, and removing a `[require]`
     entirely. These passed under the catalogue's
     consumer; some are conditionally safe under specific access
     patterns (e.g. add-field and reorder-fields rely on named field
     access — a positional-init consumer would flip both).

   A note rather than a fourth category: Slang accepts some `int`↔`float`
   mismatches as implicit conversions (silently or with a warning) —
   `change-return-type`, `change-method-return-type`, `change-param-type`,
   `change-field-type`. Three of those passed; one warned. They all
   reflect the same implicit-conversion rule observed once at the
   function-return level and seen again at field, parameter, and
   interface-method-return positions; they are not independent
   evidence of a structurally distinct kind of break. For digest
   purposes, treat type changes as breaking.

3. **The digest mechanism is not a single slangc artifact today.**
   Building it means combining the IR (for structural surface — note
   that the IR captures the *unspecialized* generic form, which is
   what a digest would actually hash), per-symbol capability DNF
   extraction, and a canonicalization pass that strips identifiers
   the catalogue showed are invisible. This is the spec-deferral the
   sketch already calls for, but now the catalogue gives a (limited)
   set of concrete acceptance criteria for it. The "no MISS observed
   for the binary" claim that motivates building on the binary form
   is fragile at this sample size — see the Limitations bullet on
   sample size.

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
  dynamic dispatch via an interface-typed value (`IShape s = sq; s.area()`),
  positional struct init (`Point{4,5}`), `inout`/`out` parameters,
  aliased types, `extension`-defined methods, or generic constraints
  binding multiple interfaces. Some catalogue "passes" verdicts are
  conditional on the consumer's access pattern — adding or reordering
  struct fields would likely flip to "breaks" under a positional-init
  consumer.

- **Single compilation target.** All cases compile to `-target spirv
  -stage compute`. The capability findings depend on the default
  spirv profile; a glsl, hlsl, or metal consumer might flip the
  same-group vs cross-group classification of `[require]` changes.

- **Mutation gaps.** Categories arguably belonging in a full
  "what's breaking?" study but not exercised here: `inout`/`out`
  parameter mutability, free-function ↔ method moves, `extension`
  add/remove, operator overloads (`__init`, `operator+`),
  `enum` cases (add/remove/reorder), attributes other than `[require]`
  (`[mutating]`, `[ForceInline]`), removing an overload from a set
  the consumer relies on, default values for generic type-args,
  interface-inheritance changes, visibility tightening on generics
  or interfaces, **changing the module's own declared name** (an
  obvious break that would also stress the digest's identity
  handling), and **import-graph changes** (the library adding,
  removing, or version-bumping a transitive `import`).

- **Sample size.** 29 cases — by ACTUAL outcome, 16 passes (2 of
  which are identity controls; 14 real mutations) and 13 breaks
  (3 of which are ok-err cases where the library no longer compiles).
  Enough to find direction and to surface a definite MISS in the
  text-dump digest. Not enough to claim bounds on the binary's miss
  rate; the breaking-case denominator is small enough that "no
  misses observed" should not be read as "sound."

- **Prediction calibration.** Each case has an `EXPECTED` outcome
  that was authored before the case's category was run. Categories
  were added incrementally (commits `fecf74a` → `68a01d4` → `ac6c146`
  → `ae44dab`), so predictions in later batches were informed by
  findings in earlier ones. Specifically: the function-level run
  surfaced the int→float warning surprise (`change-return-type`
  predicted breaks, actually passes); the type-level
  (`change-field-type`) and interface-level (`change-method-return-type`)
  predictions for analogous int→float mutations were then authored
  knowing slangc's implicit-conversion lenience. They're consistency
  checks, not blind predictions. Only the function-level
  `change-return-type` was truly blind for the int↔float family.

  Tally for the catalogue as a whole: of 29 cases, 27 were a-priori
  predictions when authored (2 of those are trivial identity
  controls); 2 (`types/change-field-type`,
  `interfaces/change-method-return-type`) are confirmatory consistency
  checks of the int↔float coercion rule observed in
  `functions/change-return-type`.

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

1. **Second consumer.** Add a consumer that uses dynamic dispatch
   via an interface-typed value (`IShape s = sq; s.area()`),
   positional struct init, and `inout`/`out` parameters. Re-run the
   catalogue against both. The matrix will distinguish
   "unconditionally non-breaking" from "non-breaking under this
   access pattern" — and likely flip several catalogue "passes" to
   conditional verdicts.

2. **Prototype the digest.** Build a canonicalised signature from
   `-dump-module` text plus per-symbol capability DNF extraction, and
   re-run the probe. That tests the synthesis's load-bearing claim
   ("the hard part is defining the digest precisely") rather than
   asserting it.

3. **Multi-target sweep on capabilities.** Re-run the capability
   cases under at least one additional `-target` (glsl or hlsl),
   since the same-group / cross-group classification of `[require]`
   changes depends on the
   target.
