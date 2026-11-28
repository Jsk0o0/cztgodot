extends Node
## 便携模式入口 (autoload: Boot, 排在 Game 之前 —— Game/Mods._ready 一到就要读设置和扫 Mod)。
## 逻辑全在 Portable 类 (见该类的说明; 第三方补丁替换 game/mod_manager 字节码也不影响):
##   1. settings 双向同步 (见 sync_settings)。
##   2. 自动补 settings 的 paths/game_dir = 程序旁的 orig (补丁版 game.gd 没有 orig 回退)。
## 存档/认识度由 state/fame 直接经 Portable 写便携目录; Mod 目录由发行流水线注入的
## mod_manager.gdc (ROOT 经 Portable.path_in, 见 tools/make_portable_mods.py) 直接指到
## <程序目录>/userdata/mods —— 引擎原生路径, 不再需要目录联接。
## 非便携 (旁边没有 orig/) 时全部是空操作。

func _ready() -> void:
	Portable.sync_settings()
	Portable.heal_game_dir()
