extends Node

enum {
	FUNC_UPDATE_LAUNCHER = 0,
	FUNC_UPDATE_GAME = 1,
	FUNC_TOTAL_BYTES = 2,
	FUNC_SEND_FILE = 3,
	FUNC_QUIT = 4
}

enum {
	STATE_IDLE = 0,
	STATE_RETRY = 1,
	STATE_UPDATE_LAUNCHER = 2,
	STATE_UPDATE_GAME = 3,
	STATE_WAITING = 4,
	STATE_START_GAME = 5,
	STATE_EXIT = 6
}

enum {
	STATUS_OK = 0,
	STATUS_CONT = 1,
	STATUS_BUSY = 2,
	STATUS_NEXT = 3,
	STATUS_DONE = 4
}


const kLauncherPck: String = "LauncherClient.pck"

var os_name: String
var exe_dir: String


func _ready() -> void:
	os_name = OS.get_name()
	
	if OS.has_feature("editor"):
		exe_dir = ProjectSettings.globalize_path("res://Export") + "/"
	else:
		exe_dir = OS.get_executable_path().get_base_dir() + "/"


func update_pck() -> void:
#	var root = get_tree().get_root()
#	var main:Node2D = root.get_node("Main")
	print("Glb.update_pck()")
	if ProjectSettings.load_resource_pack("res://" + kLauncherPck, true):
#		print("pck loaded:True")
		var err: int = get_tree().change_scene("res://Temp.tscn")
		if err != OK:
			print("err:", err)
		else:
#			main.queue_free()
#			while is_instance_valid(main):
#				yield(get_tree(), "idle_frame")
			yield(get_tree(), "idle_frame")
			
			err = get_tree().change_scene("res://Main.tscn")
			if err != OK:
				print("err:", err)
		
