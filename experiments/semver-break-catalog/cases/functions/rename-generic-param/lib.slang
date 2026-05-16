module "@org/lib";

public int add(int x, int y) { return x + y; }

// Mutation: generic parameter renamed T -> U.
// Consumer uses positional generic args — should be invisible.
public U identity<U>(U x) { return x; }

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
