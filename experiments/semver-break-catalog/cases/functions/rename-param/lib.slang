module "@org/lib";

// Mutation: `add` parameter renamed x -> a.
// Consumer uses positional calls, so this should be invisible.
public int add(int a, int y) { return a + y; }

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
