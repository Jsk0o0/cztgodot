extends Node
## 便携模式入口 (autoload: Boot, 排在 Game 之前 —— Game/Mods._ready 一到就要读设置和扫 Mod)。
## 逻辑全在 Portable 类 (见该类的说明; 第三方补丁替换 game/mod_manager 字节码也不影响):
##   1. 把 user://mods 做成指向 <程序目录>/userdata/mods 的目录联接 —— 补丁版 mod_manager 扫 "user://mods"
##      时引擎直接解析到便携目录, 新机器上的 Mod 跟着游戏目录走, 不需要它的脚本配合。
##   2. 自动补 settings 的 paths/game_dir = 程序旁的 orig (补丁版 game.gd 没有 orig 回退)。
## 存档/认识度由 state/fame 直接经 Portable 写便携目录 (这两份脚本不被补丁替换)。
## 非便携 (旁边没有 orig/) 时全部是空操作。

func _ready() -> void:
	Portable.sync_settings()
	Portable.portable_subdir("mods")
	Portable.heal_game_dir()
