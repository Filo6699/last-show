shader_type spatial;
render_mode cull_disabled;
uniform vec4 tint : source_color = vec4(1.0);
uniform sampler2D albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform bool has_albedo = false;
varying float height;
varying vec3 world_point;
void vertex(){world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;height=world_point.y;}
void fragment(){
 vec3 cloth=tint.rgb;
 if(has_albedo)cloth*=texture(albedo,UV).rgb;
 // Upper canvas receives much less bounced light than the occupied lower tent.
 float canopy_falloff=mix(1.0,.44,smoothstep(5.0,33.0,height));
 // Quiet long seams and broad tension folds; avoid pixel-sized noisy weave.
 float arc=atan(world_point.z,world_point.x)*49.5;
 float seam=min(fract(arc/3.2),1.0-fract(arc/3.2));
 float stitch=1.0-.10*(1.0-smoothstep(.003,.010,seam));
 float tension=.985+.015*sin(arc*2.2+sin(height*.23));
 vec3 shaded=cloth*canopy_falloff*stitch*tension;
 // Keep the graphic stripes below eye level; high fabric recedes into shade.
 ALBEDO=mix(shaded,vec3(.075,.062,.069),smoothstep(8.0,28.0,height)*.24);
 ROUGHNESS=.96;
 SPECULAR=.12;
}
