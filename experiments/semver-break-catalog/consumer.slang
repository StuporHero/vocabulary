import "@org/lib";

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
