shader_type canvas_item;
// HD-2D（オクトパストラベラー風）の画面端を暗く落とすヴィネット。
// 全画面の ColorRect に乗せ、SubViewport の 3D 描画の上に重ねる。
render_mode unshaded;

uniform float strength : hint_range(0.0, 1.0) = 0.5;  // 端の暗さ
uniform float radius : hint_range(0.1, 1.2) = 0.85;   // 効き始める半径

void fragment() {
	vec2 d = UV - vec2(0.5);
	// アスペクト無視の素朴な円形ヴィネット（縦長画面でも自然に効く）
	float dist = length(d);
	float v = smoothstep(radius, radius - 0.5, dist);  // 中心=1, 端=0
	COLOR = vec4(0.0, 0.0, 0.0, (1.0 - v) * strength);
}
