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

	# 新场景（聚会房屋）走 tools/house/ 的多文件结构，不复用 scene_content.gd，
	# 以保证三个旧场景完全不被动到，零回归风险。
	var geom_script: Script = load("res://tools/lib/geom.gd")
	var party_script: Script = load("res://tools/house/house_party.gd")

	var build_party := func(root: Node) -> void:
		var geom = geom_script.new()
		var party = party_script.new(geom)
		party.build(root)

	var jobs: Array = [
		["living_room", Callable(content, "assemble_living_room")],
		["house_exterior", Callable(content, "assemble_house_exterior")],
		["dark_road", Callable(content, "assemble_dark_road")],
		["party_house", build_party],
	]

	for job in jobs:
		var scene_name: String = job[0]
		var builder: Callable = job[1]
		if not builder.is_valid():
			push_error("构建器无效: %s" % scene_name)
			failures.append(scene_name)
			continue
		if not _write_scene(builder, scene_name):
			failures.append(scene_name)

	if failures.is_empty():
		print("COMET scene builder: %d/%d scenes written to %s" % [jobs.size(), jobs.size(), OUT_DIR])
		quit(0)
		return
	print("COMET scene builder FAILED for: %s" % str(failures))
	quit(1)


func _write_scene(builder: Callable, scene_name: String) -> bool:
	var root := Node3D.new()
	root.name = scene_name
	var loc_script: Script = load(S_LOCATION)
	root.set_script(loc_script)

	builder.call(root)

	# 防御：构建器内部若出错（例如脚本解析失败、依赖类未索引），root 会是空的。
	# 这种情况下 pack 依然会成功，会产出「空场景」而日志却显示已生成——
	# 实测踩到过一次（party_house 生成了 0 个碰撞体、0 个热点却报成功）。
	if root.get_child_count() == 0:
		push_error("构建器未产生任何节点，场景为空: %s（检查依赖脚本是否解析失败）" % scene_name)
		root.free()
		return false

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
