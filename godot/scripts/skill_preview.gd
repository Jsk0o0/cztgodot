extends Node
## 技能预览 (make preview): 进一场战斗 (战场 41, 三人 40 级), 由 SkillViewer 用正式战斗引擎施放任意技能
## (以前这里是一套单独的简化战斗演示, 战斗系统后来的修正都没同步, 已改为直接用战斗引擎)


func _ready() -> void:
	Game.skill_viewer = true
	State.reset()
	get_tree().change_scene_to_file.call_deferred("res://scenes/field.tscn")
