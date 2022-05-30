Shader "Unlit/ToonWaterClone"
{
    Properties
    {
        _DepthGradientShallow("潜水颜色",Color) = (0,0,0,0)
        _DepthGradientDeep("深水颜色",Color) = (0,0,0,0)
        _DepthMaxDistance("最大深度",float) = 1
        _NoiseTex("噪声纹理",2D) = "White"{}
        _NoistTint("噪声强度",Range(0,1))=0.7
        _FoamDistance("泡沫距离",float) = 0
        _SurfaceNoiseScroll("运动方向",vector) = (0.03,0.03,0,0)
        _SurfaceDistortion("运动纹理",2D) = "white"{}
        _surfaceDistortionAmount("运动强度",Range(0,1))=0.27
        _FomaMaxDistance("最大泡沫",float) = 0.4
        _FomaMinDistance("最小泡沫",float) =0.04

    }
    SubShader
    {
        Tags{"Queue"="Transparent"}
        Pass
        {
            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            CGPROGRAM
            #define SMOOTHSTEP_AA 0.01
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            uniform fixed4 _DepthGradientShallow;
            uniform fixed4 _DepthGradientDeep;
            uniform fixed _DepthMaxDistance;
            sampler2D _CameraDepthTexture;
            sampler2D _NoiseTex;
            float4 _NoiseTex_ST;
            uniform fixed _NoistTint;
            uniform fixed _FoamDistance;
            float2 _SurfaceNoiseScroll;
            uniform sampler2D _SurfaceDistortion;
            float4 _SurfaceDistortion_ST;
            uniform fixed _surfaceDistortionAmount;
            sampler2D _CameraNormalsTexture;
            fixed _FomaMaxDistance;
            fixed _FomaMinDistance;

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float2 NoiseUV      : TEXCOORD0;
                float2 distortUV    : TEXCOORD3;
                float4 vertex       : SV_POSITION;
                float4 ScreenPos    : TEXCOORD1;
                float3 ViewNormal   : TEXCOORD2;
            };


            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                //计算裁剪空间下的顶点坐标的屏幕坐标
                o.ScreenPos = ComputeScreenPos(o.vertex);
                o.NoiseUV = TRANSFORM_TEX(v.uv,_NoiseTex);
                o.distortUV = TRANSFORM_TEX(v.uv,_SurfaceDistortion);
                o.ViewNormal = COMPUTE_VIEW_NORMAL;//视图空间法线
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                //UNITY_SAMPLE_DEPTH 取得r通道
                float depth = UNITY_SAMPLE_DEPTH(tex2Dproj(_CameraDepthTexture,UNITY_PROJ_COORD(i.ScreenPos))); 
                float LinearDepth = LinearEyeDepth(depth);//投影矩阵是非线性的，需要转换为线性深度
                float depthDifference = LinearDepth - i.ScreenPos.w;
                float WaterDepthDifference = saturate(depthDifference/_DepthMaxDistance);
                float4 waterColor = lerp(_DepthGradientShallow,_DepthGradientDeep,WaterDepthDifference);

                float2 distorSample = (tex2D(_SurfaceDistortion,i.distortUV).xy * 2 - 1) * _surfaceDistortionAmount;
                float2 noiseUV = float2(i.NoiseUV.x + _Time.y * _SurfaceNoiseScroll.x + distorSample.x , 
                i.NoiseUV.y+_Time.y * _SurfaceNoiseScroll.y+distorSample.y);
                float surfaceNoiseSample = tex2D(_NoiseTex,noiseUV).r;

                //通过水下表面角度调整泡沫，视图空间法线与渲染纹理法线比较（点积结果）
                float3 existingNormal = tex2Dproj(_CameraNormalsTexture,UNITY_PROJ_COORD(i.ScreenPos));
                float3 normalDot = saturate(dot(existingNormal,i.ViewNormal));
                float  fomaDistance = lerp(_FomaMaxDistance,_FomaMinDistance,normalDot);
                
                float fomaDepthDifference = saturate(depthDifference/fomaDistance);
                float surfaceNoiseCutoff = fomaDepthDifference* _NoistTint;
                
  
                //抗锯齿平滑过渡
                float surfaceNoise = smoothstep(surfaceNoiseCutoff-SMOOTHSTEP_AA,surfaceNoiseCutoff+SMOOTHSTEP_AA,surfaceNoiseSample);
                return waterColor+surfaceNoise;
                
            }
            ENDCG
        }
    }
}
