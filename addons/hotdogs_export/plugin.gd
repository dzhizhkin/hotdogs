@tool
extends EditorPlugin

## Godot при экспорте пропускает скрытые файлы, include_filter их не видит,
## поэтому .env с ключами EOS добавляем в pck вручную

var _export_plugin := EnvExportPlugin.new()


func _enter_tree() -> void:
	add_export_plugin(_export_plugin)


func _exit_tree() -> void:
	remove_export_plugin(_export_plugin)


class EnvExportPlugin extends EditorExportPlugin:
	const ENV_PATH := "res://.env"

	func _get_name() -> String:
		return "HotdogsEnv"

	func _export_begin(_features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		if not FileAccess.file_exists(ENV_PATH):
			push_error("Нет .env — кооп в сборке работать не будет")
			return
		add_file(ENV_PATH, FileAccess.get_file_as_bytes(ENV_PATH), false)
