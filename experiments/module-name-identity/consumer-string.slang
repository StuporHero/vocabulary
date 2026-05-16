import "@a/math";
import "@b/math";

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    int sum = a_marker() + b_marker();
}
