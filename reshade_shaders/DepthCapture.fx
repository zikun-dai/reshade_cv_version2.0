// DepthCapture.fx - Renders RAW (non-linearized) depth to an off-screen R32F texture
// for addon-based capture on DX12/Vulkan where direct depth stencil access fails.
// The raw depth will be converted to physical distance (meters) by game-specific C++ code.

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
    // Sample raw depth from GPU depth buffer (normalized to [0,1] by GPU)
    // Apply coordinate transformations and REVERSED flip, but NOT the final linearization
#if RESHADE_DEPTH_INPUT_IS_UPSIDE_DOWN
    texcoord.y = 1.0 - texcoord.y;
#endif
#if RESHADE_DEPTH_INPUT_IS_MIRRORED
    texcoord.x = 1.0 - texcoord.x;
#endif
    texcoord.x /= RESHADE_DEPTH_INPUT_X_SCALE;
    texcoord.y /= RESHADE_DEPTH_INPUT_Y_SCALE;
#if RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET
    texcoord.x -= RESHADE_DEPTH_INPUT_X_PIXEL_OFFSET * BUFFER_RCP_WIDTH;
#else
    texcoord.x -= RESHADE_DEPTH_INPUT_X_OFFSET / 2.000000001;
#endif
#if RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET
    texcoord.y += RESHADE_DEPTH_INPUT_Y_PIXEL_OFFSET * BUFFER_RCP_HEIGHT;
#else
    texcoord.y += RESHADE_DEPTH_INPUT_Y_OFFSET / 2.000000001;
#endif

    // Sample raw depth
    float depth = tex2Dlod(ReShade::DepthBuffer, float4(texcoord, 0, 0)).x * RESHADE_DEPTH_MULTIPLIER;

    // Apply logarithmic conversion if needed (this is GPU-side decoding, not game-specific conversion)
#if RESHADE_DEPTH_INPUT_IS_LOGARITHMIC
    const float C = 0.01;
    depth = (exp(depth * log(C + 1.0)) - 1.0) / C;
#endif

    // Apply reversed flip if needed (convert 1=near/0=far to 0=near/1=far)
#if RESHADE_DEPTH_INPUT_IS_REVERSED
    depth = 1.0 - depth;
#endif

    // IMPORTANT: Do NOT apply the final linearization step
    // Return raw normalized depth [0,1] for C++ side game-specific conversion
    return depth;
}

technique DepthCapture < hidden = true; > {
    pass {
        VertexShader  = PostProcessVS;
        PixelShader   = PS_DepthCapture;
        RenderTarget  = DepthCaptureTex;
    }
}
