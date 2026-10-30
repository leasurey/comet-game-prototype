## SceneBuilder — 离线场景构建器
##
## 用法（在 Godot 项目根目录执行）：
##   godot --headless --script res://tools/scene_builder.gd
##
## 为什么用脚本生成 .tscn 而不是手写场景文件：
##   场景文本格式对属性名、资源引用、子节点归属都很敏感，手写容易产出
##   「看起来能加载、实际节点缺失」的坏场景。由 Godot 自己 pack 出来的 .tscn
##   与编辑器生成的完全一致，且结果仍可在编辑器里继续调整。
##
## 本脚本不属于游戏运行时代码，运行时不引用它。

extends SceneTree

const OUT_DIR := "res://scenes/locations/"
const S_LOCATION := "res://core/location.gd"
const S_CONTENT := "res://tools/scene_content.gd"


func _initialize() -> void:
	print("COMET scene builder starting...")

	var content_script: Script = load(S_CONTENT)
	if content_script == null:
		push_error("无法加载 tools/scene_content.gd")
		quit(1)
		return

	var failures: Array = []
	var content = content_script.new()

	var targets: Array = [
		["living_room", "assemble_living_room"],
		["house_exterior", "assemble_house_exterior"],
		["dark_road", "assemble_dark_road"],
	]

	for pair in targets:
		var scene_name: String = pair[0]
		var method: String = pair[1]
		if not content.has_method(method):
			push_error("缺少构建方法: %s" % method)
			failures.append(scene_name)
			continue
		if not _write_scene(content, scene_name, method):
			failures.append(scene_name)

	if failures.is_empty():
		print("COMET scene builder: 3/3 scenes written to %s" % OUT_DIR)
		quit(0)
		return
	print("COMET scene builder FAILED for: %s" % str(failures))
	quit(1)


func _write_scene(content, scene_name: String, method: String) -> bool:
	var root := Node3D.new()
	root.name = scene_name
	var loc_script: Script = load(S_LOCATION)
	root.set_script(loc_script)

	content.call(method, root)

	# 只给后代设置 owner；root 自身不能把 owner 设成自己，否则引擎会报错。
	_claim_children(root, root)

	var packed := PackedScene.new()
	var pack_err := packed.pack(root)
	if pack_err != OK:
		push_error("pack 失败: %s (错误码 %d)" % [scene_name, pack_err])
		root.free()
		return false

	var path := OUT_DIR + scene_name + ".tscn"
	var save_err := ResourceSaver.save(packed, path)
	if save_err != OK:
		push_error("保存失败: %s (错误码 %d)" % [path, save_err])
		root.free()
		return false

	root.free()
	print("  built %s" % path)
	return true


func _claim_children(parent: Node, owner: Node) -> void:
	for child in parent.get_children():
		child.owner = owner
		_claim_children(child, owner)
