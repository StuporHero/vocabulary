module "@org/lib";

public int add(int x, int y) { return x + y; }

public T identity<T>(T x) { return x; }

// Mutation: Point fields reordered (y before x). Consumer uses named access —
// should be invisible at source level, though buffer layout differs.
public struct Point
{
    public int y;
    public int x;
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
