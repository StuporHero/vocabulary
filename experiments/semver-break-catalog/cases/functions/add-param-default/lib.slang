module "@org/lib";

// Mutation: `add` gains a third parameter `z` with a default value.
public int add(int x, int y, int z = 0) { return x + y + z; }

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
