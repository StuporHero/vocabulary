# Module-name identity in Slang

## Question

The Slang user-guide says `module` declarations and `import` statements
both accept a string-literal form (`module "@ns/foo";`,
`import "@ns/foo";`). It does **not** say what the linker keys module
identity on. The question for `docs/sketch.md` decision 3.1 (identity
& versioning) is whether scoped names like `@ns/foo` can serve as
real module identity — i.e. whether `import "@a/math";` and
`import "@b/math";` produce two distinct modules in one compilation,
or collapse to a single `math` and collide.

## Slangc version

Pinned in `run.sh`: **v2026.8.1**, Linux x86_64 prebuilt from the
official GitHub release.

## Method

`run.sh` downloads slangc once (into the gitignored
`experiments/.slang-bin/`), then runs the test matrix below and
appends to `results.txt`. Each case discards the `-o` output;
diagnostics are what matter.

| # | Case                                                | Expected if identity is full-string | Expected if identity is basename |
|---|-----------------------------------------------------|-------------------------------------|----------------------------------|
| 1 | Precompile `module "@a/math";` to `.slang-module`   | success                             | success                          |
| 1b| Precompile `module "@b/math";` to `.slang-module`   | success                             | success                          |
| 2 | Precompile `module plain_math;` (identifier form)   | success                             | success                          |
| 3 | Consumer `import "@a/math"; import "@b/math";`      | **success** (both markers resolve)  | redefinition error               |
| 4 | Consumer `import plain_math;` (identifier form)     | success                             | success                          |
| 5 | Consumer `import "@a/math";` only                   | success                             | success                          |
| 6 | `module "conflict";` (string) ↔ `import conflict;`  | success                             | success                          |
| 7 | Two modules both export `dup_marker()`              | **ambiguity** at call site          | redefinition at load time        |

## Findings

All cases produce the outcomes consistent with **full-string identity**:

- Case 3 compiled clean. Both `a_marker()` and `b_marker()` resolved
  in a single compute shader; the linker accepted `@a/math` and
  `@b/math` as distinct modules.
- Case 7 produced **ambiguity, not redefinition**:

  ```
  error[E39999]: ambiguous call to 'dup_marker' with arguments of type ()
   --> consumer-collide.slang:8:25
  note[E40011]: candidate: public func dup_marker() -> int
   --> pkgs-collide/@b/dup.slang:3:12
  note[E40011]: candidate: public func dup_marker() -> int
   --> pkgs-collide/@a/dup.slang:3:12
  ```

  Both modules loaded successfully; the error is at the call site
  where the consumer has to choose between two equally-good
  candidates. If identity had keyed on the basename `dup`, the second
  `import` would have failed before the call site was even checked.

- Case 6 confirmed that a module declared with `module "conflict";`
  (string-form, plain identifier inside) is reachable via
  `import conflict;` (identifier form). The two import flavors unify
  on plain-identifier names.

Conclusion: **Slang keys module identity on the full string-form
name.** `@ns/foo` is a real disambiguator, not just file-naming sugar.

## Implication for `docs/sketch.md` decision 3.1

This rules in a previously-uncertain option: the registry *could*
use scoped names directly as module identity (`module "@nvidia/math";`,
`import "@nvidia/math";`), without needing the manifest's
`name` → `module` munging.

That doesn't make it the right choice — costs flagged in the prior
discussion still apply: ugly imports in consumer code, source coupled
to the registry's namespace convention, no help with multi-version
coexistence, and (case 7) two packages that legitimately both export
the same symbol still need disambiguation at the call site. But the
mechanism is real and the load-bearing claim ("the linker won't
collapse them") is settled in its favor.

## Re-running

```
bash experiments/module-name-identity/run.sh
```

Idempotent. Reuses `experiments/.slang-bin/slangc` after the first
download. Output paths in `results.txt` are stable (no temp-dir
churn) so reruns diff cleanly aside from the timestamp line.
