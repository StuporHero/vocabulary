module "@org/lib";

public int add(int x, int y) { return x + y; }

public T identity<T>(T x) { return x; }

public struct Point
{
    public int x;
    public int y;
}

// Mutation: IShape.area() renamed to IShape.surface(); Square's impl updated.
// Consumer still calls sq1.area() — should break.
public interface IShape
{
    int surface();
}

public struct Square : IShape
{
    public int side;
    public int surface() { return side * side; }
}

public int total_area<S : IShape>(S a, S b) { return a.surface() + b.surface(); }
