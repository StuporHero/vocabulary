module "@org/lib";

public int add(int x, int y) { return x + y; }

public T identity<T>(T x) { return x; }

public struct Point
{
    public int x;
    public int y;
}

// Mutation: IShape gains `perimeter()` with a default implementation.
// Square does NOT override it. Consumer doesn't call it.
public interface IShape
{
    int area();
    int perimeter() { return 0; }
}

public struct Square : IShape
{
    public int side;
    public int area() { return side * side; }
}

public int total_area<S : IShape>(S a, S b) { return a.area() + b.area(); }
