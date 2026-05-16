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

// Mutation: Square no longer conforms to IShape (still has area() method).
// Consumer calls total_area<Square>(...) which requires S : IShape — should break.
public struct Square
{
    public int side;
    public int area() { return side * side; }
}

public int total_area<S : IShape>(S a, S b) { return a.area() + b.area(); }
