module "@org/lib";

// Mutation: `add` first parameter changes int -> float.
// Consumer passes int literals — implicit widening.
public int add(float x, int y) { return int(x) + y; }

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
