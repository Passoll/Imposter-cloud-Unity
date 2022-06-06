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

float _HeightScale;
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

float2 ParallaxMapping(float4 frame, inout float depth)
{
	
	float depthlod = 1.0;
	//高度层数
	float numLayers = 5;
	//每层高度
	float layerHeight = 1.0 / numLayers;
	// 当前层级高度
	float currentLayerHeight = 0.5;
	//视点方向偏移总量
	float2 P = frame.xy * _HeightScale / _Frames; 
	//每层高度uv偏移量
	float2 deltaTexCoords = P / numLayers;
	//当前 UV
	float2  currentTexCoords = frame.zw;
	float currentHeightMapValue = 0.5 - tex2Dlod( _Normals, float4( frame.zw, 0, depthlod)).a ;
	while(currentLayerHeight < currentHeightMapValue)
	{
		// 按高度层级进行 UV 偏移
		currentTexCoords += deltaTexCoords;
		// 从高度贴图采样获取的高度
		currentHeightMapValue = 0.5 - tex2Dlod( _Normals, float4( currentTexCoords, 0, depthlod)).a;  
		// 采样点高度
		currentLayerHeight -= layerHeight;  
	}
	//前一个采样的点
	float2 prevTexCoords = currentTexCoords - deltaTexCoords;
    
	//线性插值
	float afterHeight  = currentHeightMapValue - currentLayerHeight;
	float beforeHeight = tex2Dlod( _Normals, float4( prevTexCoords, 0, depthlod)).a - (currentLayerHeight - layerHeight);
	float weight =  afterHeight / (afterHeight - beforeHeight);
	float2 finalTexCoords = prevTexCoords * weight + currentTexCoords * (1.0 - weight);
	
    depth = afterHeight;
	return finalTexCoords;  
}

inline void RayPlaneIntersectionUV( float3 normal, float3 rayPosition, float3 rayDirection, inout float2 uvs, inout float3 localNormal )
{
	//这一步相当于有3个frame ，求出不同的frame（和ray dir有一定偏差的虚构local space里求出这个虚拟uv值）
	// n = normal 在这里也就是camera的向量
	// p0 = (0, 0, 0) assuming center as zero
	// l0 = ray position
	// l = ray direction
	// solving to:
	// t = distance along ray that intersects the plane = ((p0 - l0) . n) / (l . n)
	// p = intersection point
	
	// ray intersect plane algorithm
	float lDotN = dot( rayDirection, normal ); // l . n
	float p0l0DotN = dot( -rayPosition, normal ); // (p0 - l0) . n

	float t = p0l0DotN / lDotN; // if > 0 then it's intersecting，equal to 
	float3 p = rayDirection * t + rayPosition; //intersectpoint

	// create frame UVs 构建在物体空间中的虚拟物体空间
	float3 upVector = float3( 0, 1, 0 );//in the objectspace up
	float3 tangent = normalize( cross( upVector, normal ) + float3( -0.001, 0, 0 ) );
	float3 bitangent = cross( tangent, normal );

	float frameX = dot( p, tangent );//已知向量球xy轴位置
	float frameZ = dot( p, bitangent );

	uvs = -float2( frameX, frameZ ); // why negative???

	if( t <= 0.0 ) // not intersecting
		uvs = 0;
	
	float3x3 LocalTovlocal = float3x3( tangent,bitangent,normal); // TBN (same as doing separate dots?, assembly looks the same)
	localNormal = normalize( mul( LocalTovlocal, rayDirection ) );//ray in virtual local of virtual frame,original annotation is false
	//这里normalize的原因是近似认为它为z？
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
	
	//float3 worldCameraPos = worldOrigin + mul( UNITY_MATRIX_I_V, perspective ).xyz;
	float3 worldCameraPos = _WorldSpaceCameraPos;
	float3 objectCameraPosition = mul( ai_WorldToObject, float4( worldCameraPos, 1 ) ).xyz - _Offset.xyz; //ray origin
	float3 objectCameraDirection = normalize( objectCameraPosition );

	// Create orthogonal vectors to define the billboard
	float3 upVector = float3( 0,1,0 );
	float3 objectHorizontalVector = normalize( cross( objectCameraDirection, upVector ) );
	float3 objectVerticalVector = cross( objectHorizontalVector, objectCameraDirection );

	// Billboard
	float2 uvExpansion = imp.vertex.xy;//obj space,本来平均分的四个象限顶点就会被变换到billboard的位置
	float3 billboard = objectHorizontalVector * uvExpansion.x + objectVerticalVector * uvExpansion.y;

	float3 localDir = billboard - objectCameraPosition; // ray direction 后续相当于插值为任意的ray

	// Octahedron Frame
	float2 frameOcta = VectortoOctahedron( objectCameraDirection.xzy ) * 0.5 + 0.5;

	// Setup for octahedron
	float2 prevOctaFrame = frameOcta * prevFrame;//frame的具体数字
	float2 baseOctaFrame = floor( prevOctaFrame );//frame的整数
	float2 fractionOctaFrame = ( baseOctaFrame * fractionsFrame );//整数frame在整张贴图的uv位置(归零）

	// Octa 1
	float2 octaFrame1 = ( baseOctaFrame * fractionsPrevFrame ) * 2.0 - 1.0;//将uv重新映射回-1到1
	float3 octa1WorldY = OctahedronToVector( octaFrame1 ).xzy;//重构回世界的向量，并且交换zy轴？? 或者我可以理解为叉乘么？

	float3 octa1LocalY;
	float2 uvFrame1;
	RayPlaneIntersectionUV( octa1WorldY, objectCameraPosition, localDir, /*inout*/ uvFrame1, /*inout*/ octa1LocalY );
	//因为normal不是相机空间完整的y（有3frame）所以这里localy是octa的camera space normal是乘上了parallax，得到的就是采样原图的基础偏移向量parallax1
	//但这里的parallax不是针对pom的，而是针对frame采样上的
	float2 uvParallax1 = octa1LocalY.xy * fractionsFrame * parallax / octa1LocalY.z; //  octa1LocalY.xy = viewDir.xy / viewDir.z    
	uvFrame1 = ( uvFrame1 * fractionsUVscale + 0.5 ) * fractionsFrame + fractionOctaFrame;// for converting the parallax into 0-1 (originally -0.5-0.5) then find the all count
	imp.uvsFrame1 = float4( uvParallax1, uvFrame1) - float4( 0, 0, uvOffset );

	// Octa 2
	float2 fractPrevOctaFrame = frac( prevOctaFrame );//frame的小数，是具体uv
	float2 cornerDifference = lerp( float2( 0,1 ) , float2( 1,0 ) , saturate( ceil( ( fractPrevOctaFrame.x - fractPrevOctaFrame.y ) ) ));
	float2 octaFrame2 = ( ( baseOctaFrame + cornerDifference ) * fractionsPrevFrame ) * 2.0 - 1.0;

	float3 octa2WorldY = OctahedronToVector( octaFrame2 ).xzy;


	float3 octa2LocalY;
	float2 uvFrame2;
	RayPlaneIntersectionUV( octa2WorldY, objectCameraPosition, localDir, /*inout*/ uvFrame2, /*inout*/ octa2LocalY );

	float2 uvParallax2 = octa2LocalY.xy * fractionsFrame * parallax / octa2LocalY.z;
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

	float2 uvParallax3 = octa3LocalY.xy * fractionsFrame * parallax / octa3LocalY.z;
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
	
    //using zw to sample the depth，the real pom here
	//0-1 ~ -0.5 0.5
	/*
	float4 parallaxSample1 = tex2Dbias( _Normals, float4( imp.uvsFrame1.zw, 0, depthBias) );
	float2 parallax1 =  (( 0.5 - parallaxSample1.a ) * imp.uvsFrame1.xy ) + imp.uvsFrame1.zw;
	float4 parallaxSample2 = tex2Dbias( _Normals, float4( imp.uvsFrame2.zw, 0, depthBias) );
	float2 parallax2 = ( ( 0.5 - parallaxSample2.a ) * imp.uvsFrame2.xy ) + imp.uvsFrame2.zw;
	float4 parallaxSample3 = tex2Dbias( _Normals, float4( imp.uvsFrame3.zw, 0, depthBias) );
	float2 parallax3 = ( ( 0.5 - parallaxSample3.a ) * imp.uvsFrame3.xy ) + imp.uvsFrame3.zw;
	*/
	float depth1, depth2, depth3;
	float2 parallax1 = ParallaxMapping(imp.uvsFrame1, depth1);
	float2 parallax2 = ParallaxMapping(imp.uvsFrame2, depth2);
	float2 parallax3 = ParallaxMapping(imp.uvsFrame3, depth3);
	
	// albedo alpha
	float4 albedo1 = tex2Dbias( _Albedo, float4( parallax1, 0, textureBias) );
	float4 albedo2 = tex2Dbias( _Albedo, float4( parallax2, 0, textureBias) );
	float4 albedo3 = tex2Dbias( _Albedo, float4( parallax3, 0, textureBias) );
	float4 blendedAlbedo = albedo1 * weights.x + albedo2 * weights.y + albedo3 * weights.z;

	baseTex.rgb = blendedAlbedo.rgb;
	// early clip
	baseTex.a = saturate( blendedAlbedo.r - _ClipMask);
	


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
	
	// normal depth
	float4 normals1 = tex2Dbias( _Normals, float4( parallax1, 0, textureBias) );
	float4 normals2 = tex2Dbias( _Normals, float4( parallax2, 0, textureBias) );
	float4 normals3 = tex2Dbias( _Normals, float4( parallax3, 0, textureBias) );
	float4 blendedNormal = normals1 * weights.x  + normals2 * weights.y + normals3 * weights.z;

	//float3 localNormal = blendedNormal.rgb * 2.0 - 1.0;
	//localNormal = float3(localNormal.x,localNormal.y,localNormal.z);
	float3 localNormal = blendedNormal.rgb
	;
	//float3 worldNormal = UnityObjectToWorldNormal( localNormal);
	Normal = localNormal;
	
	float3 viewPos = imp.viewPos.xyz;
	float depthOffset = ( ( depth1 * weights.x + depth2 * weights.y + depth3 * weights.z ) - 0.5 /** 2.0 - 1.0*/ ) /** 0.5*/ * _DepthSize * length( ai_ObjectToWorld[ 2 ].xyz );
	
		
	// else add offset normally
	viewPos.z += depthOffset;

	worldPos = mul( UNITY_MATRIX_I_V, float4( viewPos.xyz, 1 ) ).xyz;
	clipPos = mul( UNITY_MATRIX_P, float4( viewPos, 1 ) );
	
	clipPos.xyz /= clipPos.w;
	
	if( UNITY_NEAR_CLIP_VALUE < 0 )
		clipPos = clipPos * 0.5 + 0.5;
}

#endif
