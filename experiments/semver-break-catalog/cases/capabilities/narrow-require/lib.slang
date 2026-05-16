module "@org/lib";

// Mutation: requirement narrowed from spirv_1_3 down to spirv_1_0.
// Any caller that could satisfy 1_3 also satisfies 1_0 — should pass.
[require(spirv_1_0)]
public int needs_caps() { return 42; }
