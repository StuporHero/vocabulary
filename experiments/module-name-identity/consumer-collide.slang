import "@a/dup";
import "@b/dup";

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    int sum = dup_marker();
}
