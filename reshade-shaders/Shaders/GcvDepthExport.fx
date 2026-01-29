// Offscreen depth export for CV capture (DX12/Vulkan path)
#include "ReShade.fxh"

float4 PS_GcvDepthExport(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    float d = ReShade::GetLinearizedDepth(uv);
    float farp = (RESHADE_DEPTH_LINEARIZATION_FAR_PLANE > 0.0) ? RESHADE_DEPTH_LINEARIZATION_FAR_PLANE : 1.0;
    return float4(d * farp, 0.0, 0.0, 1.0);
}

technique GcvDepthExport
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader  = PS_GcvDepthExport;
    }
}
