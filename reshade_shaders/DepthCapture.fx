// DepthCapture.fx - Renders linearized depth to an off-screen R32F texture
// for addon-based capture on DX12/Vulkan where direct depth stencil access fails.

#include "ReShade.fxh"

texture DepthCaptureTex {
    Width  = BUFFER_WIDTH;
    Height = BUFFER_HEIGHT;
    Format = R32F;
};

sampler DepthCaptureSamp {
    Texture = DepthCaptureTex;
};

float PS_DepthCapture(float4 pos : SV_Position, float2 texcoord : TEXCOORD) : SV_Target {
    return ReShade::GetLinearizedDepth(texcoord);
}

technique DepthCapture < hidden = true; > {
    pass {
        VertexShader  = PostProcessVS;
        PixelShader   = PS_DepthCapture;
        RenderTarget  = DepthCaptureTex;
    }
}
