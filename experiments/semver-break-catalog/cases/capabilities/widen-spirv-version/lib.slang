module "@org/lib";

// Mutation: requirement widened from spirv_1_3 up to spirv_1_5.
// Outcome depends on what the consumer's compute entry can satisfy
// under the default profile — recording the empirical answer.
[require(spirv_1_5)]
public int needs_caps() { return 42; }
