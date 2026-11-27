class_name Portable
extends RefCounted
## 便携模式 (第三方「懒人补丁包」等发行补丁会整体替换 game/mod_manager 等脚本的字节码, 所以便携检测放这个独立类里,
## 存档 (state.gd) / 认识度 (fame.gd) 只依赖本类, 打过补丁的发行包同样生效):
##   程序 (或编辑器工程上级目录) 旁边有 orig/ 时, 整个文件夹是自包含便携包:
##   设置/存档/Mod/认识度放 <程序目录>/userdata/, 原版目录取 <程序目录>/orig (运行期音频), 拷到别的机器进度即完整带走
##   没有 orig/ 时 root 为空, 所有路径等于原来的 user:// 位置, 行为不变
static var root := _find()

static func _find() -> String:
	for base in [OS.get_executable_path().get_base_dir(), ProjectSettings.globalize_path("res://").path_join("..")]:
		if base == "" or base == "." or not DirAccess.dir_exists_absolute(base.path_join("orig")):
			continue
		DirAccess.make_dir_recursive_absolute(base.path_join("userdata"))
		return base
	return ""

static func path_in(sub: String, user_default: String) -> String:
	return root.path_join("userdata").path_join(sub) if root != "" else user_default
