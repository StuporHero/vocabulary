module "@org/lib";

// Mutation: `add` return type narrows from int to float.
// Consumer assigns to `int s` — implicit narrowing conversion.
public float add(int x, int y) { return float(x + y); }

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
