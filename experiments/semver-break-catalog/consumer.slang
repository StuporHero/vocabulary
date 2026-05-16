import "@org/lib";

// Each call below assigns to an unused local. That's deliberate:
// slangc's type-check (which decides pass/fail for the catalogue)
// runs before any dead-code elimination, so the unused locals are
// load-bearing for break detection. Don't replace them with a
// buffer store — that would introduce its own surface contact.
[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    int s = add(1, 2);
    int i = identity<int>(3);

    Point p;
    p.x = 4;
    p.y = 5;

    Square sq1;
    sq1.side = 6;
    Square sq2;
    sq2.side = 7;

    int a = sq1.area();
    int t = total_area<Square>(sq1, sq2);
}
