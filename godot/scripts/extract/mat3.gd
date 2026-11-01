extends RefCounted
## 3×3 矩阵小工具 (行主序 PackedFloat64Array 9 个数), 给模型导出用: 行列式、乘法、极分解 (= numpy svd 的 U @ Vt)


static func from4(m: PackedFloat32Array) -> PackedFloat64Array:
	return PackedFloat64Array([m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10]])


static func det(a: PackedFloat64Array) -> float:
	return a[0] * (a[4] * a[8] - a[5] * a[7]) - a[1] * (a[3] * a[8] - a[5] * a[6]) + a[2] * (a[3] * a[7] - a[4] * a[6])


static func mul(a: PackedFloat64Array, b: PackedFloat64Array) -> PackedFloat64Array:
	var c := PackedFloat64Array()
	c.resize(9)
	for i in 3:
		for j in 3:
			c[i * 3 + j] = a[i * 3] * b[j] + a[i * 3 + 1] * b[3 + j] + a[i * 3 + 2] * b[6 + j]
	return c


static func transpose(a: PackedFloat64Array) -> PackedFloat64Array:
	return PackedFloat64Array([a[0], a[3], a[6], a[1], a[4], a[7], a[2], a[5], a[8]])


## 对称矩阵的特征分解 (Jacobi 旋转): 返回 [特征值 3 个, 特征向量矩阵 V (列 = 特征向量)]
static func eig_sym(s: PackedFloat64Array) -> Array:
	var a := s.duplicate()
	var v := PackedFloat64Array([1, 0, 0, 0, 1, 0, 0, 0, 1])
	for sweep in 50:
		var off := absf(a[1]) + absf(a[2]) + absf(a[5])
		if off < 1e-15:
			break
		for pq in [[0, 1], [0, 2], [1, 2]]:
			var p: int = pq[0]
			var q: int = pq[1]
			var apq := a[p * 3 + q]
			if absf(apq) < 1e-300:
				continue
			var theta := (a[q * 3 + q] - a[p * 3 + p]) / (2.0 * apq)
			var t := signf(theta) / (absf(theta) + sqrt(theta * theta + 1.0)) if theta != 0.0 else 1.0
			var c := 1.0 / sqrt(t * t + 1.0)
			var sn := t * c
			for k in 3:   # A = Jᵀ A J
				var akp := a[k * 3 + p]
				var akq := a[k * 3 + q]
				a[k * 3 + p] = c * akp - sn * akq
				a[k * 3 + q] = sn * akp + c * akq
			for k in 3:
				var apk := a[p * 3 + k]
				var aqk := a[q * 3 + k]
				a[p * 3 + k] = c * apk - sn * aqk
				a[q * 3 + k] = sn * apk + c * aqk
			for k in 3:
				var vkp := v[k * 3 + p]
				var vkq := v[k * 3 + q]
				v[k * 3 + p] = c * vkp - sn * vkq
				v[k * 3 + q] = sn * vkp + c * vkq
	return [[a[0], a[4], a[8]], v]


static func _col(m: PackedFloat64Array, j: int) -> Vector3:
	return Vector3(m[j], m[3 + j], m[6 + j])


## 极分解的正交因子 U Vᵀ (R = U Σ Vᵀ); 奇异值为 0 的方向用叉积补全
static func polar(r: PackedFloat64Array) -> PackedFloat64Array:
	var e := eig_sym(mul(transpose(r), r))
	var ev: Array = e[0]
	var v: PackedFloat64Array = e[1]
	var order := [0, 1, 2]
	order.sort_custom(func(x, y): return ev[x] > ev[y])
	var vs: Array = []
	var us: Array = []
	var mx := maxf(float(ev[order[0]]), 0.0)
	for k in order:
		var vk := _col(v, k)
		vs.append(vk)
		var sig := sqrt(maxf(float(ev[k]), 0.0))
		if sig > 1e-9 * maxf(sqrt(mx), 1e-300):
			var rv := Vector3(r[0] * vk.x + r[1] * vk.y + r[2] * vk.z, r[3] * vk.x + r[4] * vk.y + r[5] * vk.z, r[6] * vk.x + r[7] * vk.y + r[8] * vk.z)
			us.append(rv / sig)
		else:
			us.append(null)
	# 补全
	if us[0] == null:
		us[0] = Vector3(1, 0, 0)
	if us[1] == null:
		var a: Vector3 = us[0]
		var t := Vector3(0, 1, 0) if absf(a.y) < 0.9 else Vector3(1, 0, 0)
		us[1] = (t - a * a.dot(t)).normalized()
	if us[2] == null:
		us[2] = (us[0] as Vector3).cross(us[1])
		if Vector3(vs[0]).cross(vs[1]).dot(vs[2]) < 0:
			us[2] = -us[2]
	var out := PackedFloat64Array()
	out.resize(9)
	for i in 3:
		for j in 3:
			var acc := 0.0
			for k in 3:
				acc += (us[k] as Vector3)[i] * (vs[k] as Vector3)[j]
			out[i * 3 + j] = acc
	return out
