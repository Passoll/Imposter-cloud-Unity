#ifndef AYSEIMPOSTORS_INCLUDED
#define AYSEIMPOSTORS_INCLUDED
#define AI_CLIP_NEIGHBOURS_FRAMES 1

struct ImposterData
{
	half3 viewPos;
	half4 octaFrame;
	half4 uvsFrame1;
	half4 uvsFrame2;
	half4 uvsFrame3;
	half4 vertex;
	half3 normal;
};

float2 VectortoOctahedron( float3 N )
{
	N /= dot( 1.0, abs(N) );
	if( N.z <= 0 )
	{
		N.xy = ( 1 - abs(N.yx) ) * ( N.xy >= 0 ? 1.0 : -1.0 );
	}
	return N.xy;
}

float2 VectortoHemiOctahedron( float3 N )
{
	N.xy /= dot( 1.0, abs(N) );
	return float2( N.x + N.y, N.x - N.y );
}

float3 OctahedronToVector( float2 Oct )
{
	float3 N = float3( Oct, 1.0 - dot( 1.0, abs(Oct) ) );
	if( N.z < 0 )
	{
		N.xy = ( 1 - abs(N.yx) ) * ( N.xy >= 0 ? 1.0 : -1.0 );
	}
	return normalize(N);
}

sampler2D _Albedo;
sampler2D _Normals;
sampler2D _Emission;

float _FramesX;
float _FramesY;
float _Frames;
float _ImpostorSize;
float _Parallax;
float _TextureBias;
float _ClipMask;
float _DepthSize;
float4 _Offset;
float4 _AI_SizeOffset;
float _EnergyConservingSpecularColor;

	#define AI_SAMPLEBIAS(textureName, samplerName, coord2, bias) tex2Dbias( textureName, float4( coord2, 0, bias) )
	#define ai_ObjectToWorld unity_ObjectToWorld
	#define ai_WorldToObject unity_WorldToObject

	#define AI_INV_TWO_PI  UNITY_INV_TWO_PI
	#define AI_PI          UNITY_PI
	#define AI_INV_PI      UNITY_INV_PI

inline void RayPlaneIntersectionUV( float3 normal, float3 rayPosition, float3 rayDirection, inout float2 uvs, inout float3 localNormal )
{
	// n = normal
	// p0 = (0, 0, 0) assuming center as zero
	// l0 = ray position
	// l = ray direction
	// solving to:
	// t = distance along ray that intersects the plane = ((p0 - l0) . n) / (l . n)
	// p = intersection point

	float lDotN = dot( rayDirection, normal ); // l . n
	float p0l0DotN = dot( -rayPosition, normal ); // (p0 - l0) . n

	float t = p0l0DotN / lDotN; // if > 0 then it's intersecting
	float3 p = rayDirection * t + rayPosition;

	// create frame UVs
	float3 upVector = float3( 0, 1, 0 );
	float3 tangent = normalize( cross( upVector, normal ) + float3( -0.001, 0, 0 ) );
	float3 bitangent = cross( tangent, normal );

	float frameX = dot( p, tangent );
	float frameZ = dot( p, bitangent );

	uvs = -float2( frameX, frameZ ); // why negative???

	if( t <= 0.0 ) // not intersecting
		uvs = 0;
	
	float3x3 worldToLocal = float3x3( tangent, bitangent, normal ); // TBN (same as doing separate dots?, assembly looks the same)
	localNormal = normalize( mul( worldToLocal, rayDirection ) );
}

inline void OctaImpostorVertex( inout ImposterData imp )
{
	// Inputs
	float2 uvOffset = _AI_SizeOffset.zw;
	float parallax = -_Parallax; // check sign later
	float UVscale = _ImpostorSize;
	float framesXY = _Frames;
	float prevFrame = framesXY - 1;
	float3 fractions = 1.0 / float3( framesXY, prevFrame, UVscale );
	float fractionsFrame = fractions.x;
	float fractionsPrevFrame = fractions.y;
	float fractionsUVscale = fractions.z;

	// Basic data
	float3 worldOrigin = 0;
	float4 perspective = float4( 0, 0, 0, 1 );
	// if there is no perspective we offset world origin with a 5000 view dir vector, otherwise we use the original world position
	
	float3 worldCameraPos = worldOrigin + mul( UNITY_MATRIX_I_V, perspective ).xyz;

	float3 objectCameraPosition = mul( ai_WorldToObject, float4( worldCameraPos, 1 ) ).xyz - _Offset.xyz; //ray origin
	float3 objectCameraDirection = normalize( objectCameraPosition );

	// Create orthogonal vectors to define the billboard
	float3 upVector = float3( 0,1,0 );
	float3 objectHorizontalVector = normalize( cross( objectCameraDirection, upVector ) );
	float3 objectVerticalVector = cross( objectHorizontalVector, objectCameraDirection );

	// Billboard
	float2 uvExpansion = imp.vertex.xy;
	float3 billboard = objectHorizontalVector * uvExpansion.x + objectVerticalVector * uvExpansion.y;

	float3 localDir = billboard - objectCameraPosition; // ray direction

	// Octahedron Frame
	float2 frameOcta = VectortoOctahedron( objectCameraDirection.xzy ) * 0.5 + 0.5;

	// Setup for octahedron
	float2 prevOctaFrame = frameOcta * prevFrame;
	float2 baseOctaFrame = floor( prevOctaFrame );
	float2 fractionOctaFrame = ( baseOctaFrame * fractionsFrame );

	// Octa 1
	float2 octaFrame1 = ( baseOctaFrame * fractionsPrevFrame ) * 2.0 - 1.0;
	float3 octa1WorldY = OctahedronToVector( octaFrame1 ).xzy;

	float3 octa1LocalY;
	float2 uvFrame1;
	RayPlaneIntersectionUV( octa1WorldY, objectCameraPosition, localDir, /*inout*/ uvFrame1, /*inout*/ octa1LocalY );

	float2 uvParallax1 = octa1LocalY.xy * fractionsFrame * parallax;
	uvFrame1 = ( uvFrame1 * fractionsUVscale + 0.5 ) * fractionsFrame + fractionOctaFrame;
	imp.uvsFrame1 = float4( uvParallax1, uvFrame1) - float4( 0, 0, uvOffset );

	// Octa 2
	float2 fractPrevOctaFrame = frac( prevOctaFrame );
	float2 cornerDifference = lerp( float2( 0,1 ) , float2( 1,0 ) , saturate( ceil( ( fractPrevOctaFrame.x - fractPrevOctaFrame.y ) ) ));
	float2 octaFrame2 = ( ( baseOctaFrame + cornerDifference ) * fractionsPrevFrame ) * 2.0 - 1.0;
	#ifdef _HEMI_ON
		float3 octa2WorldY = HemiOctahedronToVector( octaFrame2 ).xzy;
	#else
		float3 octa2WorldY = OctahedronToVector( octaFrame2 ).xzy;
	#endif

	float3 octa2LocalY;
	float2 uvFrame2;
	RayPlaneIntersectionUV( octa2WorldY, objectCameraPosition, localDir, /*inout*/ uvFrame2, /*inout*/ octa2LocalY );

	float2 uvParallax2 = octa2LocalY.xy * fractionsFrame * parallax;
	uvFrame2 = ( uvFrame2 * fractionsUVscale + 0.5 ) * fractionsFrame + ( ( cornerDifference * fractionsFrame ) + fractionOctaFrame );
	imp.uvsFrame2 = float4( uvParallax2, uvFrame2) - float4( 0, 0, uvOffset );

	// Octa 3
	float2 octaFrame3 = ( ( baseOctaFrame + 1 ) * fractionsPrevFrame  ) * 2.0 - 1.0;
	#ifdef _HEMI_ON
		float3 octa3WorldY = HemiOctahedronToVector( octaFrame3 ).xzy;
	#else
		float3 octa3WorldY = OctahedronToVector( octaFrame3 ).xzy;
	#endif

	float3 octa3LocalY;
	float2 uvFrame3;
	RayPlaneIntersectionUV( octa3WorldY, objectCameraPosition, localDir, /*inout*/ uvFrame3, /*inout*/ octa3LocalY );

	float2 uvParallax3 = octa3LocalY.xy * fractionsFrame * parallax;
	uvFrame3 = ( uvFrame3 * fractionsUVscale + 0.5 ) * fractionsFrame + ( fractionOctaFrame + fractionsFrame );
	imp.uvsFrame3 = float4( uvParallax3, uvFrame3) - float4( 0, 0, uvOffset );

	
	imp.octaFrame = 0;
	imp.octaFrame.xy = prevOctaFrame;
	#if AI_CLIP_NEIGHBOURS_FRAMES
	imp.octaFrame.zw = fractionOctaFrame;
	#endif

	imp.vertex.xyz = billboard + _Offset.xyz;
	imp.normal.xyz = objectCameraDirection;
	
	imp.viewPos.xyz = UnityObjectToViewPos( imp.vertex.xyz );
}

inline void OctaImpostorFragment(in ImposterData imp,inout half3 Normal, inout float4 clipPos, inout float3 worldPos,inout half4 baseTex )
{
	float depthBias = -1.0;
	float textureBias = _TextureBias;

	// Weights
	float2 fraction = frac( imp.octaFrame.xy );
	float2 invFraction = 1 - fraction;
	float3 weights;
	weights.x = min( invFraction.x, invFraction.y );
	weights.y = abs( fraction.x - fraction.y );
	weights.z = min( fraction.x, fraction.y );

	float4 parallaxSample1 = tex2Dbias( _Normals, float4( imp.uvsFrame1.zw, 0, depthBias) );
	float2 parallax1 = ( ( 0.5 - parallaxSample1.a ) * imp.uvsFrame1.xy ) + imp.uvsFrame1.zw;
	float4 parallaxSample2 = tex2Dbias( _Normals, float4( imp.uvsFrame2.zw, 0, depthBias) );
	float2 parallax2 = ( ( 0.5 - parallaxSample2.a ) * imp.uvsFrame2.xy ) + imp.uvsFrame2.zw;
	float4 parallaxSample3 = tex2Dbias( _Normals, float4( imp.uvsFrame3.zw, 0, depthBias) );
	float2 parallax3 = ( ( 0.5 - parallaxSample3.a ) * imp.uvsFrame3.xy ) + imp.uvsFrame3.zw;

	// albedo alpha
	float4 albedo1 = tex2Dbias( _Albedo, float4( parallax1, 0, textureBias) );
	float4 albedo2 = tex2Dbias( _Albedo, float4( parallax2, 0, textureBias) );
	float4 albedo3 = tex2Dbias( _Albedo, float4( parallax3, 0, textureBias) );
	float4 blendedAlbedo = albedo1 * weights.x + albedo2 * weights.y + albedo3 * weights.z;

	baseTex.rgb = blendedAlbedo.rgb;
	// early clip
	baseTex.a = ( blendedAlbedo.a - _ClipMask );
	


	// use it only if your impostors show small artifacts at edges at some rotations
	//#define AI_CLIP_NEIGHBOURS_FRAMES
	#if AI_CLIP_NEIGHBOURS_FRAMES
		float t = ceil( fraction.x - fraction.y );
		float4 cornerDifference = float4( t, 1 - t, 1, 1 );

		float2 step_1 = ( parallax1 - imp.octaFrame.zw ) * _Frames;
		float4 step23 = ( float4( parallax2, parallax3 ) -  imp.octaFrame.zwzw ) * _Frames - cornerDifference;

		step_1 = step_1 * (1-step_1);
		step23 = step23 * (1-step23);

		float3 steps;
		steps.x = step_1.x * step_1.y;
		steps.y = step23.x * step23.y;
		steps.z = step23.z * step23.w;
		steps = step(-steps, 0);
	
		float final = dot( steps, weights );

		clip( final - 0.5 );
	#endif

	
/*	//other samplling
	// Emission Occlusion
	float4 mask1 = tex2Dbias( _Emission, float4( parallax1, 0, textureBias) );
	float4 mask2 = tex2Dbias( _Emission, float4( parallax2, 0, textureBias) );
	float4 mask3 = tex2Dbias( _Emission, float4( parallax3, 0, textureBias) );
	float4 blendedMask = mask1 * weights.x  + mask2 * weights.y + mask3 * weights.z;
	o.Emission = blendedMask.rgb;
	o.Occlusion = blendedMask.a;

	// Specular Smoothness
	float4 spec1 = AI_SAMPLEBIAS( _Specular, sampler_Specular, parallax1, textureBias);
	float4 spec2 = AI_SAMPLEBIAS( _Specular, sampler_Specular, parallax2, textureBias);
	float4 spec3 = AI_SAMPLEBIAS( _Specular, sampler_Specular, parallax3, textureBias);
	float4 blendedSpec = spec1 * weights.x  + spec2 * weights.y + spec3 * weights.z;
	o.Specular = blendedSpec.rgb;
	o.Smoothness = blendedSpec.a;
*/

	
	// normal depth
	float4 normals1 = tex2Dbias( _Normals, float4( parallax1, 0, textureBias) );
	float4 normals2 = tex2Dbias( _Normals, float4( parallax2, 0, textureBias) );
	float4 normals3 = tex2Dbias( _Normals, float4( parallax3, 0, textureBias) );
	float4 blendedNormal = normals1 * weights.x  + normals2 * weights.y + normals3 * weights.z;

	float3 localNormal = blendedNormal.rgb * 2.0 - 1.0;
	float3 worldNormal = normalize( mul( (float3x3)ai_ObjectToWorld, localNormal ) );
	Normal = worldNormal;

	float3 viewPos = imp.viewPos.xyz;
	float depthOffset = ( ( parallaxSample1.a * weights.x + parallaxSample2.a * weights.y + parallaxSample3.a * weights.z ) - 0.5 /** 2.0 - 1.0*/ ) /** 0.5*/ * _DepthSize * length( ai_ObjectToWorld[ 2 ].xyz );
	
		
	// else add offset normally
	viewPos.z += depthOffset;

	worldPos = mul( UNITY_MATRIX_I_V, float4( viewPos.xyz, 1 ) ).xyz;
	clipPos = mul( UNITY_MATRIX_P, float4( viewPos, 1 ) );
	
	clipPos.xyz /= clipPos.w;
	
	if( UNITY_NEAR_CLIP_VALUE < 0 )
		clipPos = clipPos * 0.5 + 0.5;
}

#endif
