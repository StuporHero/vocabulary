// String-form module name with a scope prefix. The user-guide
// permits string-form module/import names
// (`user-guide/04-modules-and-access-control.md` lines 80-86); the
// string content is opaque to the language. The prior
// module-name-identity experiment confirmed `@org/name` works as a
// real identity at link time. The shape matches the registry naming
// decided in docs/sketch.md §3.1.
module "@org/lib";

public int add(int x, int y) { return x + y; }

public T identity<T>(T x) { return x; }

public struct Point
{
    public int x;
    public int y;
}

public interface IShape
{
    int area();
}

public struct Square : IShape
{
    public int side;
    public int area() { return side * side; }
}

public int total_area<S : IShape>(S a, S b) { return a.area() + b.area(); }
