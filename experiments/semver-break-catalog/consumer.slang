import "@org/lib";

// Each call below assigns to an unused local. That's deliberate:
// type-checking operates on the source AST and must succeed before
// the IR is built; dead-code elimination operates on the IR. Type
// errors at any call site here therefore surface as compilation
// failures regardless of whether the local is ever read. Don't
// replace these locals with a buffer store — that would introduce
// its own public-surface contact (the buffer binding) and confuse
// the catalogue.
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
