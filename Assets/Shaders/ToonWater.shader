﻿Shader "Roystan/Toon/Water Tut"
{
    Properties
    {
		// What color the water will sample when the surface below is shallow.
		_DepthGradientShallow("Depth Gradient Shallow", Color) = (0.325, 0.807, 0.971, 0.725)

		// What color the water will sample when the surface below is at its deepest.
		_DepthGradientDeep("Depth Gradient Deep", Color) = (0.086, 0.407, 1, 0.749)

		// Maximum distance the surface below the water will affect the color gradient.
		_DepthMaxDistance("Depth Maximum Distance", Float) = 1

		// Color to render the foam generated by objects intersecting the surface.
		_FoamColor("Foam Color", Color) = (1,1,1,1)

		// Noise texture used to generate waves.
		_SurfaceNoise("Surface Noise", 2D) = "white" {}

		// Speed, in UVs per second the noise will scroll. Only the xy components are used.
		_SurfaceNoiseScroll("Surface Noise Scroll Amount", Vector) = (0.03, 0.03, 0, 0)

		// Values in the noise texture above this cutoff are rendered on the surface.
		_SurfaceNoiseCutoff("Surface Noise Cutoff", Range(0, 1)) = 0.777

		// Red and green channels of this texture are used to offset the
		// noise texture to create distortion in the waves.
		_SurfaceDistortion("Surface Distortion", 2D) = "white" {}	

		// Multiplies the distortion by this value.
		_SurfaceDistortionAmount("Surface Distortion Amount", Range(0, 1)) = 0.27

		// Control the distance that surfaces below the water will contribute
		// to foam being rendered.
		_FoamMaxDistance("Foam Maximum Distance", Float) = 0.4
		_FoamMinDistance("Foam Minimum Distance", Float) = 0.04		
    }
    SubShader
    {
		Tags
		{
			"Queue" = "Transparent"
		}

        Pass
        {
			// Transparent "normal" blending.
			Blend SrcAlpha OneMinusSrcAlpha
			ZWrite Off

            CGPROGRAM
			#define SMOOTHSTEP_AA 0.01

            #pragma vertex vert
            #pragma fragment frag

            #include "UnityCG.cginc"


			//Alpha blend 对泡沫颜色和水颜色混合
			float4 alphaBlend(float4 top, float4 bottom)
			{
				float3 color = (top.rgb * top.a) + (bottom.rgb * (1 - top.a));
				float alpha = top.a + bottom.a * (1 - top.a);

				return float4(color, alpha);
			}

            struct appdata
            {
                float4 vertex : POSITION;
				float4 uv : TEXCOORD0;
				float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;	
				float2 noiseUV : TEXCOORD0;
				float2 distortUV : TEXCOORD1;
				float4 screenPosition : TEXCOORD2;
				float3 viewNormal : NORMAL;
            };

			sampler2D _SurfaceNoise;
			float4 _SurfaceNoise_ST;

			sampler2D _SurfaceDistortion;
			float4 _SurfaceDistortion_ST;

            v2f vert (appdata v)
            {
                v2f o;

                o.vertex = UnityObjectToClipPos(v.vertex);
				o.screenPosition = ComputeScreenPos(o.vertex);
				o.distortUV = TRANSFORM_TEX(v.uv, _SurfaceDistortion);
				o.noiseUV = TRANSFORM_TEX(v.uv, _SurfaceNoise);
				o.viewNormal = COMPUTE_VIEW_NORMAL;//水面的视图空间法线

                return o;
            }

			float4 _DepthGradientShallow;
			float4 _DepthGradientDeep;
			float4 _FoamColor;

			float _DepthMaxDistance;
			float _FoamMaxDistance;
			float _FoamMinDistance;
			float _SurfaceNoiseCutoff;
			float _SurfaceDistortionAmount;

			float2 _SurfaceNoiseScroll;

			sampler2D _CameraDepthTexture;
			sampler2D _CameraNormalsTexture;

            float4 frag (v2f i) : SV_Target
            {
				//_CameraDepthTexture内置变量，存储深度图，由相机上的脚本CamreaDepthTextureMode中设置
				//深度图会直接存储到变量中，使用屏幕空间坐标进行采样。
				//得到的值是非线性的，需要将其转到线性空间下
				float existingDepth01 = tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPosition)).r;
				float existingDepthLinear = LinearEyeDepth(existingDepth01);

				//根据湖的深度进行颜色渐变。湖底到相机的距离减去湖面到相机的距离（W分量中存储像素在空间中到相机的距离）
				float depthDifference = existingDepthLinear - i.screenPosition.w;

				//计算湖水的深度的百分比
				//在深色和浅色之间插值渐变颜色
				float waterDepthDifference01 = saturate(depthDifference / _DepthMaxDistance);
				float4 waterColor = lerp(_DepthGradientShallow, _DepthGradientDeep, waterDepthDifference01);
				
				//采样法线缓冲纹理
				//使用采样得到的法线和视图法线做点积，使用点积结果控制泡沫大小
				//根据深度值计算泡沫
				float3 existingNormal = tex2Dproj(_CameraNormalsTexture, UNITY_PROJ_COORD(i.screenPosition));
				float3 normalDot = saturate(dot(existingNormal, i.viewNormal));
				float foamDistance = lerp(_FoamMaxDistance, _FoamMinDistance, normalDot);
				float foamDepthDifference01 = saturate(depthDifference / foamDistance);
				float surfaceNoiseCutoff = foamDepthDifference01 * _SurfaceNoiseCutoff;

				//泡沫纹理采样，*2-1 将结果从（0，1）映射为（-1，1）来回扰动
				//水面纹理UV扰动并混合上泡沫纹理，使用扰动后的UV对水面纹理采样
				float2 distortSample = (tex2D(_SurfaceDistortion, i.distortUV).xy * 2 - 1) * _SurfaceDistortionAmount;
				float2 noiseUV = float2((i.noiseUV.x + _Time.y * _SurfaceNoiseScroll.x) + distortSample.x, 
				(i.noiseUV.y + _Time.y * _SurfaceNoiseScroll.y) + distortSample.y);
				float surfaceNoiseSample = tex2D(_SurfaceNoise, noiseUV).r;
				//泡沫边缘抗锯齿，在两个很小的值之间插值
				float surfaceNoise = smoothstep(surfaceNoiseCutoff - SMOOTHSTEP_AA, surfaceNoiseCutoff + SMOOTHSTEP_AA, surfaceNoiseSample);

				//泡沫颜色
				float4 surfaceNoiseColor = _FoamColor;
				surfaceNoiseColor.a *= surfaceNoise;

				// Use normal alpha blending to combine the foam with the surface.
				return alphaBlend(surfaceNoiseColor, waterColor);
				//return waterColor;
            }
            ENDCG
        }
    }
}