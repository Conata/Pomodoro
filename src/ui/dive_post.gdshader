shader_type canvas_item;
// 探索ビュー用スクリーンスペース・ポストプロセス。
// カラーグレーディング＋ブルーム＋擬似DoF（ティルトシフト）＋ビネット。
// area で指定した矩形（＝探索ステージ）内だけに適用し、外は透過。

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform vec4 area = vec4(0.0, 0.0, 1.0, 1.0);            // min.xy / max.zw（SCREEN_UV）
uniform float bloom_intensity : hint_range(0.0, 2.0) = 0.65;
uniform float bloom_threshold : hint_range(0.0, 1.0) = 0.62;
uniform float blur_radius : hint_range(0.0, 8.0) = 2.2;
uniform float dof_strength : hint_range(0.0, 1.0) = 0.85;  // ティルトシフトのボケ量
uniform float focus_y : hint_range(0.0, 1.0) = 0.5;        // ピント中心（SCREEN_UV y）
uniform float focus_band : hint_range(0.01, 0.5) = 0.16;   // ピントの帯（半幅）
uniform float vignette : hint_range(0.0, 1.0) = 0.38;
uniform float saturation : hint_range(0.0, 2.0) = 1.16;
uniform float contrast : hint_range(0.5, 1.5) = 1.06;
uniform float brightness : hint_range(0.5, 1.5) = 1.0;
uniform vec3 shadow_tint = vec3(0.55, 0.62, 0.98);        // 影を青紫へ
uniform vec3 highlight_tint = vec3(1.10, 0.88, 1.05);     // ハイライトを赤紫(ネオン)へ
uniform float grade_amount : hint_range(0.0, 1.0) = 0.8;

vec3 ring_blur(vec2 uv, vec2 px, float r) {
	vec3 c = texture(screen_tex, uv).rgb;
	for (int i = 0; i < 8; i++) {
		float a = 0.7853982 * float(i); // 2π/8
		c += texture(screen_tex, uv + vec2(cos(a), sin(a)) * px * r).rgb;
	}
	return c / 9.0;
}

vec3 grade(vec3 c) {
	c = (c - 0.5) * contrast + 0.5;
	c *= brightness;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation);
	vec3 toned = mix(c * shadow_tint, c * highlight_tint, smoothstep(0.15, 0.85, l));
	return max(mix(c, toned, grade_amount), vec3(0.0));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	if (uv.x < area.x || uv.x > area.z || uv.y < area.y || uv.y > area.w) {
		COLOR = vec4(0.0); // 範囲外は何もしない（下のピクセルをそのまま）
	} else {
		vec2 px = SCREEN_PIXEL_SIZE;
		vec3 base = texture(screen_tex, uv).rgb;
		// 擬似DoF：ピント帯から離れるほどボカす
		float dof = clamp((abs(uv.y - focus_y) - focus_band) / max(focus_band, 0.001), 0.0, 1.0);
		vec3 blurred = ring_blur(uv, px, blur_radius * (0.7 + 2.0 * dof));
		vec3 col = mix(base, blurred, dof * dof_strength);
		// ブルーム：明部を抽出してボカしたものを加算
		vec3 bright = max(blurred - bloom_threshold, vec3(0.0)) / max(1.0 - bloom_threshold, 0.001);
		col += bright * bloom_intensity;
		// カラーグレーディング
		col = grade(col);
		// ビネット（area内座標）
		vec2 auv = (uv - area.xy) / max(area.zw - area.xy, vec2(0.001));
		float d = distance(auv, vec2(0.5, 0.52));
		col *= mix(1.0, smoothstep(0.9, 0.35, d), vignette);
		COLOR = vec4(col, 1.0);
	}
}
