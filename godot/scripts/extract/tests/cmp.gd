extends RefCounted
## 测试用: 两份 JSON 数据深度比较, 数字允许 tol 误差; 返回差异路径列表 (最多 limit 条)


static func diff(a: Variant, b: Variant, tol := 1e-6, path := "", out: Array = [], limit := 20) -> Array:
	if out.size() >= limit:
		return out
	var na := typeof(a) in [TYPE_INT, TYPE_FLOAT]
	var nb := typeof(b) in [TYPE_INT, TYPE_FLOAT]
	if na and nb:
		if absf(float(a) - float(b)) > tol * maxf(1.0, absf(float(a))):
			out.append("%s: %s != %s" % [path, a, b])
	elif typeof(a) != typeof(b):
		out.append("%s: type %s != %s (%s / %s)" % [path, type_string(typeof(a)), type_string(typeof(b)), str(a).left(60), str(b).left(60)])
	elif a is Dictionary:
		for k in a:
			if not b.has(k):
				out.append("%s/%s: missing" % [path, k])
			else:
				diff(a[k], b[k], tol, "%s/%s" % [path, k], out, limit)
		for k in b:
			if not a.has(k):
				out.append("%s/%s: extra" % [path, k])
	elif a is Array:
		if a.size() != b.size():
			out.append("%s: len %d != %d" % [path, a.size(), b.size()])
		for i in mini(a.size(), b.size()):
			diff(a[i], b[i], tol, "%s[%d]" % [path, i], out, limit)
	elif a != b:
		out.append("%s: %s != %s" % [path, str(a).left(80), str(b).left(80)])
	return out
