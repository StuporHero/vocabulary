# Experiments

Small, throwaway-friendly probes used to settle factual questions
that come up while writing `docs/sketch.md`. Each subdirectory is
self-contained: source fixtures, a reproducible `run.sh`, captured
`results.txt`, and a README explaining the question, method, findings,
and what the finding implies for the sketch.

The Slang compiler binary itself is downloaded by each experiment's
`run.sh` into `experiments/.slang-bin/` (gitignored). Re-running an
experiment is idempotent once the binary is cached.

| Experiment                                                | Question                                                                                   | Status |
|-----------------------------------------------------------|--------------------------------------------------------------------------------------------|--------|
| [`module-name-identity/`](module-name-identity/README.md) | Does Slang's linker key module identity on the full string form (`@ns/foo`) or just the basename? | Settled: full-string. |
| [`semver-break-catalog/`](semver-break-catalog/README.md) | Which kinds of public-API mutations break a downstream consumer, and do existing slangc artifacts work as a signature digest? | Catalogued: 30 cases + digest probe. |
