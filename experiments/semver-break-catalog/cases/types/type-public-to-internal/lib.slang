module "@org/lib";

public int add(int x, int y) { return x + y; }

public T identity<T>(T x) { return x; }

// Mutation: whole Point type loses `public`. Consumer references it directly — should break.
struct Point
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
