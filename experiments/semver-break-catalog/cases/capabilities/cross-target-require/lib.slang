module "@org/lib";

// Mutation: requirement switched from a spirv atom to an HLSL/SM atom.
// Consumer compiles to spirv — should not satisfy _sm_6_5.
//
// Slang also emits `warning[E36113]: using internal capability name`
// for `_sm_6_5` (it resolves to a `_Internal` atom). That warning is
// incidental to the test — the load-bearing diagnostic is
// `error[E36107]: unavailable features in entry point`, which fires
// regardless of the atom's "internal" status.
[require(hlsl, _sm_6_5)]
public int needs_caps() { return 42; }
