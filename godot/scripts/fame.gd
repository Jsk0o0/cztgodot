class_name Fame
extends RefCounted
## 认识度 (原版链表 0x9edbc0, 存在游戏目录 fame.dat, 跨存档共享; 我们存 user://fame.json):
##   怪物 id → 进度 (每进一次战斗 +5, 收服 +10, …; 达到 100 记为完全认识), 道具 id (曾经得到过)
##   记载页「人」「物」两个页签按这里显示
const PATH := "user://fame.json"
static var _data: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	if FileAccess.file_exists(PATH):
		var v: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
		if v is Dictionary:
			_data = v
	if not _data.has("monsters"):
		_data.monsters = {}
	if not _data.has("items"):
		_data.items = {}


static func save() -> void:
	_load()
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_data))


## 0x44c5d7(id, 增量, 0, 0)
static func add_monster(id: int, n: int) -> void:
	_load()
	var k := str(id)
	var e: Array = _data.monsters.get(k, [0, 0])   # [进度, 完全认识]
	if int(e[1]) == 0:
		e[0] = int(e[0]) + n
		if int(e[0]) >= 100:
			e[1] = 1
	_data.monsters[k] = e
	save()


static func monster(id: int) -> Array:
	_load()
	return _data.monsters.get(str(id), [])


## 该字段是否已知: 进度 ≥ 阈值 或曾经完全认识
static func known(id: int, threshold: int) -> bool:
	var e := monster(id)
	return e.size() > 0 and (int(e[0]) >= threshold or int(e[1]) == 1)


static func monsters() -> Array:
	_load()
	return _data.monsters.keys().map(func(x): return int(x))


static func add_item(id: int) -> void:
	_load()
	if not _data.items.has(str(id)):
		_data.items[str(id)] = 1
		save()


static func items() -> Array:
	_load()
	return _data.items.keys().map(func(x): return int(x))
