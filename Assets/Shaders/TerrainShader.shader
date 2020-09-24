Shader "Custom/TerrainShader"
{
	// TODO: I need to support custom shader inspector for this to hide
	// scale/offset for normal map using NoScaleOffset.
	Properties
	{
		[Header(Surface)]
		[MainColor] _BaseColor("Base Color", Color) = (1, 1, 1,1)
		[MainTexture] _BaseMap("Base Map", 2D) = "white" {}

		// TODO: Pack the following into a half4 and add support to mask map
		// splitting now as I've not implemented custom shader editor yet and
		// this will make it look nices in the UI
		_Metallic("Metallic", Range(0, 1)) = 1.0
		[NoScaleOffset]_MetallicSmoothnessMap("MetalicMap", 2D) = "white" {}
		_AmbientOcclusion("AmbientOcclusion", Range(0, 1)) = 1.0
		[NoScaleOffset]_AmbientOcclusionMap("AmbientOcclusionMap", 2D) = "white" {}
		_Reflectance("Reflectance for dieletrics", Range(0.0, 1.0)) = 0.5
		_Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5

		[Toggle(_NORMALMAP)] _EnableNormalMap("Enable Normal Map", Float) = 0.0
		[Normal][NoScaleOffset]_NormalMap("Normal Map", 2D) = "bump" {}
		_NormalMapScale("Normal Map Scale", Float) = 1.0

		[Header(Emission)]
		[HDR]_Emission("Emission Color", Color) = (0,0,0,1)
	}

		SubShader
		{
			Tags{"RenderPipeline" = "UniversalRenderPipeline" "IgnoreProjector" = "True"}

			// Include material cbuffer for all passes. 
			// The cbuffer has to be the same for all passes to make this shader SRP batcher compatible.
			HLSLINCLUDE
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

			// -------------------------------------
			// Material variables. They need to be declared in UnityPerMaterial
			// to be able to be cached by SRP Batcher
			CBUFFER_START(UnityPerMaterial)
			float4 _BaseMap_ST;
			half4 _BaseColor;
			half _Metallic;
			half _AmbientOcclusion;
			half _Reflectance;
			half _Smoothness;
			half4 _Emission;
			half _NormalMapScale;
			CBUFFER_END
			ENDHLSL

			Pass
			{
				Tags{"LightMode" = "UniversalForward"}

				HLSLPROGRAM
				#pragma vertex SurfaceVertex
				#pragma fragment SurfaceFragment

				// -------------------------------------
				// Material Keywords
				#pragma shader_feature _NORMALMAP

				// -------------------------------------
				// Universal Render Pipeline keywords
				#pragma multi_compile _ _MAIN_LIGHT_SHADOWS
				#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
				#pragma multi_compile _ _SHADOWS_SOFT
				#pragma multi_compile _ DIRLIGHTMAP_COMBINED
				#pragma multi_compile _ LIGHTMAP_ON

				#ifndef CUSTOM_SHADING
#define CUSTOM_SHADING

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/BSDF.hlsl"

struct Attributes
{
	float4 positionOS   : POSITION;
	float3 normalOS     : NORMAL;
	float4 tangentOS    : TANGENT;

	float2 uv           : TEXCOORD0;
#if LIGHTMAP_ON
	float2 uvLightmap   : TEXCOORD1;
#endif
	UNITY_VERTEX_INPUT_INSTANCE_ID
};

struct Varyings
{
	float2 uv                       : TEXCOORD0;
	float2 uvLightmap               : TEXCOORD1;
	float3 positionWS               : TEXCOORD2;
	half3  normalWS                 : TEXCOORD3;

#ifdef _NORMALMAP
	half4 tangentWS                 : TEXCOORD4;
#endif

	float4 positionCS               : SV_POSITION;
};

// User defined surface data.
struct SurfaceData
{
	half3 diffuse;              // diffuse color. should be black for metals.
	half3 reflectance;          // reflectance color at normal indicence. It's monochromatic for dieletrics.
	half3 normalWS;             // normal in world space
	half  ao;                   // ambient occlusion
	half  perceptualRoughness;  // perceptual roughness. roughness = perceptualRoughness * perceptualRoughness;
	half3 emission;             // emissive color
	half  alpha;                // 0 for transparent materials, 1.0 for opaque.
};

struct LightingData
{
	Light light;
	half3 environmentLighting;
	half3 environmentReflections;
	half3 halfDirectionWS;
	half3 viewDirectionWS;
	half3 reflectionDirectionWS;
	half3 normalWS;
	half NdotL;
	half NdotV;
	half NdotH;
	half LdotH;
};

// Forward declaration of SurfaceFunction. This function must be implemented in the shader
void SurfaceFunction(Varyings IN, out SurfaceData surfaceData);

// Convert normal from tangent space to space of TBN matrix
// f.ex, if normal and tangent are passed in world space, per-pixel normal will return in world space.
half3 GetPerPixelNormal(TEXTURE2D_PARAM(normalMap, sampler_NormalMap), float2 uv, half3 normal, half4 tangent)
{
	half3 bitangent = cross(normal, tangent.xyz) * tangent.w;
	half3 normalTS = UnpackNormal(SAMPLE_TEXTURE2D(normalMap, sampler_NormalMap, uv));
	return normalize(mul(normalTS, half3x3(tangent.xyz, bitangent, normal)));
}

// Convert normal from tangent space to space of TBN matrix and apply scale to normal
half3 GetPerPixelNormalScaled(TEXTURE2D_PARAM(normalMap, sampler_NormalMap), float2 uv, half3 normal, half4 tangent, half scale)
{
	half3 bitangent = cross(normal, tangent.xyz) * tangent.w;
	half3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(normalMap, sampler_NormalMap, uv), scale);
	return normalize(mul(normalTS, half3x3(tangent.xyz, bitangent, normal)));
}

half V_Kelemen(half LoH)
{
	return 0.25 / (LoH * LoH);
}

// defined in latest URP
#if SHADER_LIBRARY_VERSION_MAJOR < 9
// Computes the world space view direction (pointing towards the viewer).
float3 GetWorldSpaceViewDir(float3 positionWS)
{
	if (unity_OrthoParams.w == 0)
	{
		// Perspective
		return _WorldSpaceCameraPos - positionWS;
	}
	else
	{
		// Orthographic
		float4x4 viewMat = GetWorldToViewMatrix();
		return viewMat[2].xyz;
	}
}
#endif

half3 EnvironmentBRDF(half3 f0, half roughness, half NdotV)
{
#if 1
	// Adapted from Unity Environment BDRF Approximation
	// mmikk
	half fresnelTerm = Pow4(1.0 - NdotV);
	half3 grazingTerm = saturate((1.0 - roughness) + f0);

	// surfaceReduction = Int D(NdotH) * NdotH * Id(NdotL>0) dH = 1/(roughness^2+1)
	half surfaceReduction = 1.0 / (roughness * roughness + 1.0);
	return lerp(f0, grazingTerm, fresnelTerm) * surfaceReduction;
#else
	// Brian Karis - Physically Based Shading in Mobile
	const half4 c0 = { -1, -0.0275, -0.572, 0.022 };
	const half4 c1 = { 1, 0.0425, 1.04, -0.04 };
	half4 r = roughness * c0 + c1;
	half a004 = min(r.x * r.x, exp2(-9.28 * NdotV)) * r.x + r.y;
	half2 AB = half2(-1.04, 1.04) * a004 + r.zw;
	return f0 * AB.x + AB.y;
	return half3(0, 0, 0);
#endif
}

#ifdef CUSTOM_LIGHTING_FUNCTION
	half4 CUSTOM_LIGHTING_FUNCTION(SurfaceData surfaceData, LightingData lightingData);
#else
	half4 CUSTOM_LIGHTING_FUNCTION(SurfaceData surfaceData, LightingData lightingData)
	{
		// 0.089 perceptual roughness is the min value we can represent in fp16
		// to avoid denorm/division by zero as we need to do 1 / (pow(perceptualRoughness, 4)) in GGX
		half perceptualRoughness = max(surfaceData.perceptualRoughness, 0.089);
		half roughness = PerceptualRoughnessToRoughness(perceptualRoughness);

		half3 environmentReflection = lightingData.environmentReflections;
		environmentReflection *= EnvironmentBRDF(surfaceData.reflectance, roughness, lightingData.NdotV);

		half3 environmentLighting = lightingData.environmentLighting * surfaceData.diffuse;
		half3 diffuse = surfaceData.diffuse * Lambert();

		// CookTorrance
		// inline D_GGX + V_SmithJoingGGX for better code generations
		half DV = DV_SmithJointGGX(lightingData.NdotH, lightingData.NdotL, lightingData.NdotV, roughness);

		// for microfacet fresnel we use H instead of N. In this case LdotH == VdotH, we use LdotH as it
		// seems to be more widely used convetion in the industry.
		half3 F = F_Schlick(surfaceData.reflectance, lightingData.LdotH);
		half3 specular = DV * F;
		half3 finalColor = (diffuse + specular) * lightingData.light.color * lightingData.NdotL;
		finalColor += environmentReflection + environmentLighting + surfaceData.emission;
		return half4(finalColor, surfaceData.alpha);
	}
#endif

Varyings SurfaceVertex(Attributes IN)
{
	Varyings OUT;

	// VertexPositionInputs contains position in multiple spaces (world, view, homogeneous clip space)
	// The compiler will strip all unused references.
	// Therefore there is more flexibility at no additional cost with this struct.
	VertexPositionInputs vertexInput = GetVertexPositionInputs(IN.positionOS.xyz);

	// Similar to VertexPositionInputs, VertexNormalInputs will contain normal, tangent and bitangent
	// in world space. If not used it will be stripped.
	VertexNormalInputs vertexNormalInput = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

	OUT.uv = IN.uv;
#if LIGHTMAP_ON
	OUT.uvLightmap = IN.uvLightmap.xy * unity_LightmapST.xy + unity_LightmapST.zw;
#endif

	OUT.positionWS = vertexInput.positionWS;
	OUT.normalWS = vertexNormalInput.normalWS;

#ifdef _NORMALMAP
	// tangentOS.w contains the normal sign used to construct mikkTSpace
	// We compute bitangent per-pixel to match convertion of Unity SRP.
	// https://medium.com/@bgolus/generating-perfect-normal-maps-for-unity-f929e673fc57
	OUT.tangentWS = float4(vertexNormalInput.tangentWS, IN.tangentOS.w * GetOddNegativeScale());
#endif

	OUT.positionCS = vertexInput.positionCS;
	return OUT;
}

half4 SurfaceFragment(Varyings IN) : SV_Target
{
	SurfaceData surfaceData;
	SurfaceFunction(IN, surfaceData);

	LightingData lightingData;

	half3 viewDirectionWS = normalize(GetWorldSpaceViewDir(IN.positionWS));
	half3 reflectionDirectionWS = reflect(-viewDirectionWS, surfaceData.normalWS);

	// shadowCoord is position in shadow light space
	float4 shadowCoord = TransformWorldToShadowCoord(IN.positionWS);
	Light light = GetMainLight(shadowCoord);
	lightingData.light = light;
	lightingData.environmentLighting = SAMPLE_GI(IN.uvLightmap, SampleSH(surfaceData.normalWS), surfaceData.normalWS) * surfaceData.ao;
	lightingData.environmentReflections = GlossyEnvironmentReflection(reflectionDirectionWS, surfaceData.perceptualRoughness, surfaceData.ao);
	lightingData.halfDirectionWS = normalize(light.direction + viewDirectionWS);
	lightingData.viewDirectionWS = viewDirectionWS;
	lightingData.reflectionDirectionWS = reflectionDirectionWS;
	lightingData.normalWS = surfaceData.normalWS;
	lightingData.NdotL = saturate(dot(surfaceData.normalWS, lightingData.light.direction));
	lightingData.NdotV = saturate(dot(surfaceData.normalWS, lightingData.viewDirectionWS)) + HALF_MIN;
	lightingData.NdotH = saturate(dot(surfaceData.normalWS, lightingData.halfDirectionWS));
	lightingData.LdotH = saturate(dot(lightingData.light.direction, lightingData.halfDirectionWS));

	return CUSTOM_LIGHTING_FUNCTION(surfaceData, lightingData);
}

#endif

				// -------------------------------------
				// Textures are declared in global scope
				TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
				TEXTURE2D(_NormalMap); SAMPLER(sampler_NormalMap);
				TEXTURE2D(_MetallicSmoothnessMap);
				TEXTURE2D(_AmbientOcclusionMap);

				void SurfaceFunction(Varyings IN, out SurfaceData surfaceData)
				{
					surfaceData = (SurfaceData)0;
					float2 uv = TRANSFORM_TEX(IN.uv, _BaseMap);

					half3 baseColor = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv) * _BaseColor;
					half4 metallicSmoothness = SAMPLE_TEXTURE2D(_MetallicSmoothnessMap, sampler_BaseMap, uv);
					half metallic = _Metallic * metallicSmoothness.r;
					// diffuse color is black for metals and baseColor for dieletrics
					surfaceData.diffuse = ComputeDiffuseColor(baseColor.rgb, metallic);

					// f0 is reflectance at normal incidence. we store f0 in baseColor for metals.
					// for dieletrics f0 is monochromatic and stored in reflectance value.
					// Remap reflectance to range [0, 1] - 0.5 maps to 4%, 1.0 maps to 16% (gemstone)
					// https://google.github.io/filament/Filament.html#materialsystem/parameterization/standardparameters
					surfaceData.reflectance = ComputeFresnel0(baseColor.rgb, metallic, _Reflectance * _Reflectance * 0.16);
					surfaceData.ao = SAMPLE_TEXTURE2D(_AmbientOcclusionMap, sampler_BaseMap, uv).g * _AmbientOcclusion;
					surfaceData.perceptualRoughness = 1.0 - (_Smoothness * metallicSmoothness.a);
	#ifdef _NORMALMAP
					surfaceData.normalWS = GetPerPixelNormalScaled(TEXTURE2D_ARGS(_NormalMap, sampler_NormalMap), uv, IN.normalWS, IN.tangentWS, _NormalMapScale);
	#else
					surfaceData.normalWS = normalize(IN.normalWS);
	#endif
					surfaceData.emission = _Emission.rgb;
					surfaceData.alpha = 1.0;
				}
				ENDHLSL
			}

				// TODO: This is currently breaking SRP batcher as these passes are including
				//  a different cbuffer. We need to fix it in URP side.
				UsePass "Universal Render Pipeline/Lit/ShadowCaster"
				UsePass "Universal Render Pipeline/Lit/DepthOnly"
				UsePass "Universal Render Pipeline/Lit/Meta"
		}
}