Shader "AyseImpostors/Octahedron cloud"
{
	Properties
	{
		[NoScaleOffset]_Albedo("Albedo & Alpha", 2D) = "white" {}
		[NoScaleOffset]_Normals("Normals & Depth", 2D) = "white" {}
		_Frames("Frames", Float) = 16
		_ImpostorSize("Impostor Size", Float) = 1
		_Offset("Offset", Vector) = (0,0,0,0)
		_ClipMask("Clip", Range( 0 , 1)) = 0.5
		
		_AI_SizeOffset( "Size & Offset", Vector ) = ( 0,0,0,0 )
		_Fadedis("Fadedistance", Float) = 20
		_TextureBias("Texture Bias", Float) = -1
		_Parallax("Parallax", Range( -2 , 2)) = 1
		_DepthSize("DepthSize", Float) = 1
		_TintColor ("Color", Color) = (1,1,1,1)
		_Ambientcolor ("Color", Color) = (1,1,1,1)
	}
	
	SubShader
	{

		Tags { "IgnoreProjector" = "True" "RenderType" = "Transparent"  "Queue"="Transparent+1" }
		
		Pass
				{
					Tags { "LightMode"="ForwardBase" }
					ZWrite On
					Blend SrcAlpha OneMinusSrcAlpha
					ColorMask rgb
					Cull back
					
					CGPROGRAM 
						// compile directives
						#pragma target 3.5
						#pragma vertex vert
						#pragma fragment frag
						#include "HLSLSupport.cginc"
						#include "UnityShaderVariables.cginc"
						#include "UnityShaderUtilities.cginc"
						#include "UnityCG.cginc"
					    #include "UnityLightingCommon.cginc"

						#include "ParaImposter.cginc"
						

						fixed3 _TintColor;
						fixed3 _Ambientcolor;
						float _Fadedis;

						struct v2f
						{
							float4 pos : SV_POSITION;
							float4 uvsFrame1 : TEXCOORD1;
							float4 uvsFrame2 : TEXCOORD2;
							float4 uvsFrame3 : TEXCOORD3;
							float4 octaFrame : TEXCOORD4;
							float3 viewPos : TEXCOORD5;
						};
						
						v2f	vert (appdata_full v ) {
							v2f o;
							ImposterData imp;
							imp.vertex= v.vertex;
							
							imp.normal= v.normal;
							OctaImpostorVertex(imp);
							v.vertex = imp.vertex;
							o.pos = UnityObjectToClipPos(v.vertex);
							
							o.uvsFrame1 = imp.uvsFrame1;
							o.uvsFrame2 = imp.uvsFrame2;
							o.uvsFrame3 = imp.uvsFrame3;
							o.octaFrame = imp.octaFrame;
							o.viewPos = imp.viewPos;
							
							UNITY_TRANSFER_FOG(o,o.pos);
								
							return o;
						}

						half4 frag(v2f i) : SV_Target{
							ImposterData imp;
							imp.uvsFrame1 = i.uvsFrame1;
							imp.uvsFrame2 = i.uvsFrame2;
							imp.uvsFrame3 = i.uvsFrame3;
							imp.octaFrame = i.octaFrame;
							imp.viewPos = i.viewPos;
							half4 baseTex;
							half3 Normal;
							
							float4 clipPos;
							float3 worldPos;
							OctaImpostorFragment(imp, Normal, clipPos, worldPos, baseTex );
							i.pos.zw = clipPos.zw;


							//Houdini fix
							Normal = float3(Normal.x,Normal.z,Normal.y) * 2 - 1;
							Normal = UnityObjectToWorldNormal(Normal);
							
							fixed4 color;
							float3 lightdir = UnityWorldSpaceLightDir(worldPos);
							float3 viewdir = normalize(UnityWorldSpaceViewDir(worldPos));
							float NL = saturate(dot(Normal,lightdir));
							float VL = dot(lightdir, viewdir);
						
							half1 dis = smoothstep(-i.viewPos.z,0,_Fadedis);
							
							float lthick = baseTex.a;
						
							float thickness = 1 - exp(-5 * lthick );
							color.a = saturate(thickness * 1.8 * dis);

							float a = 0.7;
							float atten = 4;

							float3 H = lightdir + Normal * a;
							float phaselight = 2.55 * (1 + VL * VL );
							float sss = saturate(dot(viewdir,-H));
							float spe = pow(sss, atten) * (-thickness + 1);

							float3 ambient = (1-lthick) * 0.3 ;	
							float3 backlight = spe* 1.7 * _LightColor0 ;
							float3 directlight = NL * _LightColor0 * 0.3 ;
							float3 scatter = _TintColor * smoothstep(pow(1-thickness,0.6),0,0.05) / 4 / 3.14 * 4;
	
							color.rgb = scatter + directlight + backlight + ambient + 0.25 * _Ambientcolor * (1.5-NL) ;
							//return half4(baseTex.rgb ,1);

							return color;
						}
						ENDCG
				}
		}
	}
	