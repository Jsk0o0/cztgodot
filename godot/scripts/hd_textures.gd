extends GLTFDocumentExtension
## 高清贴图: 读标清 GLB 时, 把第 k 张贴图换成高清目录里的放大版 (tools/hd_textures.py)
## 发行版的 2K / 4K 包只放贴图 + 每个模型的对照表 <模型路径>.tex.json, 网格 / 动画一直读标清包。
## 在 Game._ready 注册, 对所有 GLTFDocument 生效 (含后台线程解析, 这里只读文件, 不碰场景树)


func _import_preflight(state: GLTFState, _extensions: PackedStringArray) -> Error:
	if not Game.hd or Game.hd_dir == "" or state.base_path == "":
		return ERR_SKIP
	var path := state.base_path.path_join(state.filename) + ".glb"   # filename 不带扩展名
	var root := Game.extracted_dir.rstrip("/") + "/"
	if not path.begins_with(root):
		return ERR_SKIP
	var idx := Game.hd_dir.path_join(path.substr(root.length()) + ".tex.json")
	if not FileAccess.file_exists(idx):
		return ERR_SKIP
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(idx))
	if not d is Dictionary:
		return ERR_SKIP
	state.set_additional_data(&"hd_tex", d.get("tex", []))
	state.set_additional_data(&"hd_tex_i", 0)
	return OK


## 返回 ERR_SKIP 会被引擎当错误报出来, 所以没有高清版的贴图也在这里自己解码原图
func _parse_image_data(state: GLTFState, image_data: PackedByteArray, mime_type: String, ret_image: Image) -> Error:
	var names: Array = state.get_additional_data(&"hd_tex")
	var i: int = state.get_additional_data(&"hd_tex_i")
	state.set_additional_data(&"hd_tex_i", i + 1)
	var jpg := mime_type == "image/jpeg"
	var bytes := image_data
	if i < names.size() and names[i] != null:
		var hd := FileAccess.get_file_as_bytes(Game.hd_dir.path_join("tex").path_join(str(names[i])))
		if hd.size():
			bytes = hd
			jpg = str(names[i]).ends_with(".jpg")
	return ret_image.load_jpg_from_buffer(bytes) if jpg else ret_image.load_png_from_buffer(bytes)
