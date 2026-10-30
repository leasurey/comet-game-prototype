## DataLoader — JSON 数据读取的统一入口
##
## 所有对 res://data/*.json 的访问都集中在这里，避免在业务代码里散落 FileAccess 调用。
## 返回值统一为 {"ok": bool, "error": String, "data": Variant}，调用方必须检查 ok。

class_name DataLoader
extends RefCounted


static func load_json(path: String) -> Dictionary:
	if path.is_empty():
		return _fail("路径为空")

	if not FileAccess.file_exists(path):
		return _fail("数据文件不存在: %s" % path)

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("无法打开数据文件: %s (错误码 %d)" % [path, FileAccess.get_open_error()])

	var raw := file.get_as_text()
	file.close()

	if raw.strip_edges().is_empty():
		return _fail("数据文件为空: %s" % path)

	var parser := JSON.new()
	if parser.parse(raw) != OK:
		return _fail("JSON 解析失败 %s : %s" % [path, parser.get_error_message()])

	return {"ok": true, "error": "", "data": parser.data}


static func load_dictionary(path: String) -> Dictionary:
	var result := load_json(path)
	if not bool(result.get("ok", false)):
		return {"ok": false, "error": str(result.get("error", "")), "data": {}}
	if typeof(result.get("data", null)) != TYPE_DICTIONARY:
		return {"ok": false, "error": "根节点不是对象: %s" % path, "data": {}}
	return result


static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "data": null}
