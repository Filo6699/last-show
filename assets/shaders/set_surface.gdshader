shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.3,0.24,0.18,1.0);
uniform sampler2D grain : repeat_enable, filter_linear_mipmap;
uniform float grain_scale = 0.4;
uniform float surface_kind = 0.0; // 0: timber, 1: worn performance canvas.
varying vec3 world_point;
void vertex(){world_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){
 vec2 p=world_point.xz;
 float broad=texture(grain,p*.035).r;
 float fibres=texture(grain,vec2(p.x*.028,p.y*.44)).r;
 float row=floor(p.y/.32);
 float offset=fract(sin(row*31.731)*1473.53);
 float edge=min(fract(p.y/.32),1.0-fract(p.y/.32));
 float joint=min(fract((p.x+offset*3.2)/3.2),1.0-fract((p.x+offset*3.2)/3.2));
 float seams=1.0-.14*(1.0-smoothstep(.002,.009,edge));
 seams*=1.0-.11*(1.0-smoothstep(.0004,.0015,joint));
 float board_tint=.97+.055*offset;
 vec3 wood=base_color.rgb*(.93+.13*fibres)*board_tint*seams;
 float nap=texture(grain,p*.65).r;
 vec3 canvas=base_color.rgb*(.80+.24*broad+.10*nap);
 ALBEDO=mix(wood,canvas,surface_kind);
 ROUGHNESS=mix(.77,.94,surface_kind);
 SPECULAR=mix(.28,.12,surface_kind);
}
