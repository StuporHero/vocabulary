module "@org/lib";

// Mutation: requirement switched from a spirv atom to an HLSL/SM atom.
// Consumer compiles to spirv — should not satisfy _sm_6_5.
[require(hlsl, _sm_6_5)]
public int needs_caps() { return 42; }
