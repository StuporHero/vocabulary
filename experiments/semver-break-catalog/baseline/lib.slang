// String-form module name with a scope prefix. Slang's user-guide
// permits this (`user-guide/04-modules-and-access-control.md`,
// "module" / "import" syntax) and the prior module-name-identity
// experiment confirmed it's a real identity at link time. The shape
// matches the registry naming decided in docs/sketch.md §3.1.
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
