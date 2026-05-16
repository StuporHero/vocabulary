module "@org/lib";

// Mutation: [require(spirv_1_3)] removed entirely. Function becomes
// capability-neutral. Consumer's spirv compute entry should still be
// able to call it.
public int needs_caps() { return 42; }
