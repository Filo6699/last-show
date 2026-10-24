shader_type spatial;
// Smooth painted normals on the deliberately faceted globe otherwise produce
// striped self-shadow terminators. It still casts a real shadow onto its cradle.
render_mode shadows_disabled;
varying vec3 local_point;
void vertex(){local_point=VERTEX;}
void fragment(){
 float angle=atan(local_point.z,local_point.x);
 float stripe=step(0.0,sin(angle*4.0));
 vec3 paint=mix(vec3(.37,.16,.19),vec3(.57,.49,.32),stripe);
 float equator=1.0-smoothstep(.018,.026,abs(local_point.y));
 ALBEDO=mix(paint,vec3(.11,.19,.18),equator);
 ROUGHNESS=.86;
}
