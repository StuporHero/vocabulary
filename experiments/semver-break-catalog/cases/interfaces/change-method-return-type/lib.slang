module "@org/lib";

public int add(int x, int y) { return x + y; }

public T identity<T>(T x) { return x; }

public struct Point
{
    public int x;
    public int y;
}

// Mutation: IShape.area() return type changes int -> float; Square updated.
// Consumer reads `int a = sq.area();` — implicit narrowing.
public interface IShape
{
    float area();
}

public struct Square : IShape
{
    public int side;
    public float area() { return float(side * side); }
}

public int total_area<S : IShape>(S a, S b) { return int(a.area() + b.area()); }
