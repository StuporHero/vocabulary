module "@org/lib";

public int add(int x, int y) { return x + y; }

// Mutation: identity<T> tightens to T : IShape. Consumer calls
// identity<int>(3); `int` doesn't conform to IShape — should break.
public T identity<T>(T x) where T : IShape { return x; }

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
