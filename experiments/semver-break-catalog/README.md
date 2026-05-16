# Semver-break catalogue

## Question

`docs/sketch.md` decision 3.1 says naming is settled but versioning is
not. The versioning sub-question is: **what counts as a breaking change
for a Slang module**, and whether tooling can enforce that
classification at publish time (the way Elm's package manager does for
Elm).

The catalogue answers the empirical half — for each kind of API
mutation a library author might make, does a downstream consumer that
was compiling cleanly still compile against the mutated library?
Reasoning is replaced with measurement.

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

## Findings — capability mutations (`ae44dab`)

| case | expected | actual |
| ---- | -------- | ------ |
| baseline-control     | passes | passes |
| remove-require       | passes | passes |
| narrow-require       | passes | passes |
| widen-spirv-version  | passes | passes |
| cross-target-require | breaks | breaks |

The capability story splits cleanly along "stays within the same target
family vs. switches/adds a new family." Within-family adjustments
(removing the `[require]`, narrowing from `spirv_1_3` to `spirv_1_0`,
widening from `spirv_1_3` to `spirv_1_5`) are all non-breaking for a
spirv-compute consumer compiled under the default profile.

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

Two candidate existing digest sources tested against the same 30
cases:

|                       | ok | ok-err | OVER | MISS |
| --------------------- | -- | ------ | ---- | ---- |
| `-dump-module` (text) | 14 | 3      | 12   | **1** |
| `.slang-module` (bin) | 12 | 3      | 15   | 0    |

`MISS` is the dangerous outcome — a digest that's "same" when the
consumer actually breaks would let a major change slip through as a
minor bump. The text dump misses exactly one case:
`capabilities/cross-target-require`. Verified manually: the dump for
`[require(spirv_1_3)]` is byte-identical to the dump for
`[require(hlsl, _sm_6_5)]`. The text disassembly strips capability
annotations entirely.

The binary `.slang-module` catches all 30 breaks (0 MISS), but
over-reports on 15 of the 21 passing cases — including invisible
mutations like parameter renames. It's a strict-upper-bound digest:
"if it changed, recompile and recheck," but "you might be
over-bumping."

So no existing slangc artifact is sufficient on its own:

- **Dump-module text** is selective but unsound (capability-blind).
- **Binary slang-module** is sound but loose (over-reports).

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

1. **An Elm-style publish-time check is feasible for Slang.** Most of
   the 30 mutations produce sharp, well-targeted diagnostics that a
   tool could lift verbatim. The hard part isn't compiler integration;
   it's defining the digest precisely.

2. **The digest spec has to handle four categories distinctly:**
   - **Always-breaking by signature**: function/method rename,
     parameter add (no default), remove, type/field rename or remove,
     visibility demotion, conformance removal, interface method add
     without default, associated type add without default, generic
     constraint tightening.
   - **Always-breaking by capability**: cross-target-family change in
     a `[require]` declaration.
   - **Soft-breaking**: int↔float type changes (compile with a warning
     or silently). A digest could go either way; the catalogue's
     verdict is "the consumer compiles, but the publisher probably
     meant to bump major."
   - **Safely additive**: add field, reorder fields, add overload,
     add interface method *with* default, add conformance for a new
     type, parameter/generic-param rename, within-target-family
     `[require]` adjustments.

3. **The digest mechanism is not a single slangc artifact today.**
   Building it means combining the IR (for structural surface),
   per-symbol capability DNF extraction, and a canonicalization pass
   that strips identifiers that the catalogue showed are invisible.
   This is the spec-deferral the sketch already calls for, but now
   the catalogue gives concrete acceptance criteria for it.

4. **Publish-time tooling must compile the library, not just diff
   surfaces.** Cases like `interfaces/add-method-no-default` produce
   their primary error *inside* the library (conforming type no longer
   satisfies the interface). A surface-only diff would miss this; a
   full compile catches it.

## Re-running

```
bash experiments/semver-break-catalog/run.sh
bash experiments/semver-break-catalog/probe-dump-module.sh
```

Both are idempotent. `run.sh` writes to `results.txt`;
`probe-dump-module.sh` writes to `probe-dump-module.txt`. Re-runs are
byte-identical aside from the timestamp line. The slangc binary is
downloaded once into the gitignored `experiments/.slang-bin/`.
