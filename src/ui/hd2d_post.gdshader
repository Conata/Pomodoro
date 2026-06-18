shader_type canvas_item;
// HD-2D の総仕上げ（全画面ポスト処理）。SubViewport の 3D 描画の上に乗せ、
//   1) 擬似ティルトシフト DoF：焦点帯から上下に離れるほどぼかし、ミニチュア感を出す
//      （実 DOF は Forward+/Mobile 限定なので、GL Compatibility でも効く画面後処理で再現）
//   2) ヴィネット：画面端を落として中央へ視線を誘導
// hint_screen_texture で背後（3D 合成済み）を読み、ぼかして書き戻す。
render_mode unshaded;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform float focus_center : hint_range(0.0, 1.0) = 0.5;   // くっきりさせる帯の中心（縦位置）
uniform float focus_size : hint_range(0.0, 0.5) = 0.18;    // くっきり帯の半幅
uniform float blur_strength : hint_range(0.0, 6.0) = 2.4;  // 端のぼかし量（テクセル倍率）
uniform float vig_strength : hint_range(0.0, 1.0) = 0.5;   // 端の暗さ
uniform float vig_radius : hint_range(0.1, 1.2) = 0.92;    // ヴィネットの効き始め半径

void fragment() {
	// ── ティルトシフト：焦点帯からの縦距離で blur 量を決める（端ほど強く）──
	float d = abs(UV.y - focus_center);
	float t = clamp((d - focus_size) / max(1.0 - focus_size, 0.001), 0.0, 1.0);
	float blur = t * t * blur_strength;

	vec4 col = texture(screen_tex, SCREEN_UV);
	if (blur > 0.01) {
		vec2 px = SCREEN_PIXEL_SIZE * blur;
		// 中心 + 軸 4 + 斜め 4 の 9 タップ近似ガウシアン
		vec4 acc = col * 0.25;
		acc += texture(screen_tex, SCREEN_UV + vec2(px.x, 0.0)) * 0.125;
		acc += texture(screen_tex, SCREEN_UV - vec2(px.x, 0.0)) * 0.125;
		acc += texture(screen_tex, SCREEN_UV + vec2(0.0, px.y)) * 0.125;
		acc += texture(screen_tex, SCREEN_UV - vec2(0.0, px.y)) * 0.125;
		acc += texture(screen_tex, SCREEN_UV + vec2(px.x, px.y)) * 0.0625;
		acc += texture(screen_tex, SCREEN_UV + vec2(-px.x, px.y)) * 0.0625;
		acc += texture(screen_tex, SCREEN_UV + vec2(px.x, -px.y)) * 0.0625;
		acc += texture(screen_tex, SCREEN_UV + vec2(-px.x, -px.y)) * 0.0625;
		col = acc;
	}

	// ── ヴィネット（中央=明・端=暗）──
	float vdist = length(UV - vec2(0.5));
	float v = smoothstep(vig_radius, vig_radius - 0.5, vdist);
	col.rgb *= mix(1.0 - vig_strength, 1.0, v);

	COLOR = vec4(col.rgb, 1.0);
}
