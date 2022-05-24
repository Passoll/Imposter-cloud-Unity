Shader "Custom/cloud" {
	Properties {
		_TintColor ("Color", Color) = (1,1,1,1)
		
		
		_ImposterBaseTex ("Imposter Base", 2D) = "black" {}
		_ImposterWorldNormalDepthTex ("WorldNormal+Depth", 2D) = "black" {}
		_ImposterFrames ("Frames",  float) = 16
		_ImposterSize ("Radius", float) = 1
		_ImposterOffset ("Offset", Vector) = (0,0,0,0)
		_ImposterFullSphere ("Full Sphere", float) = 1

        //_Mode ("__mode", Float) = 0.0 
        //_SrcBlend ("__src", Float) = 1.0
        //_DstBlend ("__dst", Float) = 0.0
        //_ZWrite ("__zw", Float) = 1.0
        //[HideInInspector] 
	}

    SubShader{
        Tags { "IgnoreProjector" = "True" "RenderType" = "Transparent"  "Queue"="Transparent+1" }

        Pass {
            ColorMask rgb
            ZWrite Off 
            Cull back
    	    Blend SrcAlpha OneMinusSrcAlpha
		
        CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #include "UnityCG.cginc"
            #include "UnityLightingCommon.cginc"
            #include "UnityBuiltin3xTreeLibrary.cginc"
            #include "ImposterCommon.cginc"
        
		    #pragma target 3.5
        
            half _Metallic;
            half _Cutoff;
			fixed3 _TintColor;
    
            // Add instancing support for this shader. You need to check 'Enable Instancing' on materials that use the shader.
            // See https://docs.unity3d.com/Manual/GPUInstancing.html for more information about instancing.
            // #pragma instancing_options assumeuniformscaling
            UNITY_INSTANCING_BUFFER_START(Props)
                // put more per-instance properties here
            UNITY_INSTANCING_BUFFER_END(Props)
			
            struct v2f
            {
            	float4 pos : SV_POSITION;
                float4 texCoord : TEXCOORD0; 
                float4 plane0 : TEXCOORD1;
                float4 plane1 : TEXCOORD2;
                float4 plane2 : TEXCOORD3;
                float3 tangentWorld : TANGENT;
                float3 bitangentWorld : TEXCOORD4;
                float3 normalWorld : NORMAL;
            	float4 worldpos : TEXCOORD5;
            };
    
            v2f vert (appdata_full v)
            {
            	v2f o;
                ImposterData imp;
                //NOTE modified since Unity BillboardAsset takes vertex on X Y only
                imp.vertex.xyz = float3( (v.vertex.x*2-1)*0.5, 0, (v.vertex.y*2-1)*0.5 );
                imp.vertex.w = v.vertex.w;
                imp.uv = v.texcoord.xy;
                 
                ImposterVertex(imp); 
                
                //IMP results  
                //v2f
                v.vertex = imp.vertex;
                
                //NOTE modified since Unity BillboardAsset doesnt take normal or tangent
                v.normal = float3(0,1,0);
                v.tangent = float4(1,0,0,-1);
                
                float3 normalWorld = UnityObjectToWorldDir(v.normal);
                float3 tangentWorld = UnityObjectToWorldDir(v.tangent.xyz);
                float3x3 tangentToWorld = CreateTangentToWorldPerVertex(normalWorld, tangentWorld, v.tangent.w);
                o.tangentWorld = tangentToWorld[0];
                o.bitangentWorld = tangentToWorld[1];
                o.normalWorld = tangentToWorld[2];

            	o.pos = UnityObjectToClipPos(v.vertex);
            	o.worldpos = v.vertex;
                //surface
                o.texCoord.xy = imp.uv;
                o.texCoord.zw = imp.grid;
                o.plane0 = imp.frame0;
                o.plane1 = imp.frame1;
                o.plane2 = imp.frame2;
            	return o;
            }
        
			half4 frag(v2f i) : SV_Target{
				
				ImposterData imp;
                //set inputs
                imp.uv = i.texCoord.xy;
                imp.grid = i.texCoord.zw;
                imp.frame0 = i.plane0; 
                imp.frame1 = i.plane1;
                imp.frame2 = i.plane2;
				
				half4 baseTex;
                half4 normalTex;
				ImposterSample(imp, baseTex, normalTex );
				
				//scale world normal back to -1 to 1
				half3 worldNormal = normalTex.xyz*2-1;
                
                //this works but not ideal
                worldNormal = mul( unity_ObjectToWorld, half4(worldNormal,0) ).xyz;

				//tbn
				half3 t = i.tangentWorld;
                half3 b = i.bitangentWorld;
                half3 n = i.normalWorld;

				      //from UnityStandardCore.cginc 
                #if UNITY_TANGENT_ORTHONORMALIZE
                    n = normalize(n);
            
                    //ortho-normalize Tangent
                    t = normalize (t - n * dot(t, n));
                    
                    //recalculate Binormal
                    half3 newB = cross(n, t);
                    b = newB * sign (dot (newB, b));
                #endif

				half3x3 tangentToWorld = half3x3(t, b, n); 
                
                //o well
                float3 Normal = normalize(mul(tangentToWorld, worldNormal)) ;
				fixed4 color;
				//Houdini to unity
				Normal = float3(-Normal.x,Normal.y,Normal.z);
				
				float3 lightdir = WorldSpaceLightDir(i.worldpos);
				float3 viewdir = normalize(UnityWorldSpaceViewDir(i.worldpos));
				float NL = saturate(dot(Normal,lightdir));
				float VL = dot(lightdir, viewdir);
				
				float lthick = baseTex.r;
				
				float thickness = 1 - exp(-5 * lthick );
				color.a = thickness;

				

				float a = 0.7;
				float atten = 4;

				float3 H = lightdir + Normal * a;
				float phaselight = 2.55 * (1 + VL * VL );
				float sss = saturate(dot(viewdir,-H));
				float spe = pow(sss, atten) * (-thickness + 1);
				
				color.rgb = _TintColor * thickness * phaselight * _LightColor0 / 4 / 3.14 + 0.5* NL * _LightColor0 + spe* 1.5 * _LightColor0 ;
		
				return color;
		}
			ENDCG 
    	}
		}
	}