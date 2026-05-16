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

// Mutation: new conforming type Triangle. Consumer doesn't reference it.
public struct Triangle : IShape
{
    public int base_len;
    public int height;
    public int area() { return base_len * height / 2; }
}

public int total_area<S : IShape>(S a, S b) { return a.area() + b.area(); }
