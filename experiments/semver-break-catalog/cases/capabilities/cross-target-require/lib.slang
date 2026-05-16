module "@org/lib";

// Mutation: requirement switched from a spirv atom to an HLSL/SM atom.
// `hlsl` and `spirv` are in the same mutually-exclusive group (target
// atoms), so this is a switch across that group. Consumer compiles to
// spirv — should not satisfy a require that demands hlsl.
[require(hlsl, sm_6_5)]
public int needs_caps() { return 42; }
