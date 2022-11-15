class_name FileTool extends Node


static func compress_file(p_file: String, p_method: int, p_to_dir:String = "",
		p_ext: String = "" ) -> String:
	if p_ext == "":
		p_ext = get_compress_type_ext(p_method)
	if !p_ext.begins_with("."):
		p_ext = "." + p_ext
	
	var to_path: String = ""
	var fn: String = p_file.get_file()
	if fn == "":
		return fn
	var dir: String = ""
	if p_to_dir == "":
		dir = p_file.get_base_dir()
	else:
		dir = p_to_dir.get_base_dir()
	to_path = dir + "/" + fn + p_ext
	var from_file := File.new()
	var to_file := File.new()
	var from_err = from_file.open(p_file, File.READ)
	if from_err != OK:
		printerr("Error Opening from file:", p_file)
		return ""
	var to_err = to_file.open_compressed(to_path, File.WRITE, p_method)
	if to_err != OK:
		printerr("Error Opening to file:", to_path)
		from_file.close()
		return ""
	
	var fl:int = from_file.get_len()
	var fp:int = from_file.get_position()
	while fp < fl:
		var left = fl - fp
		if left >= 8192:
			left = 8192
		to_file.store_buffer(from_file.get_buffer(left))
		fp = from_file.get_position()
		
	from_file.close()
	to_file.close()
	return to_path


static func decompress_file(p_in: String, p_out: String, p_mode: int, 
		p_signal_node: Object = null, p_signal_name: String = "") -> int:
	
	var err: int = directory_check(p_out.get_base_dir(), true)
	if err != OK: 
		return err
	
	var from_file := File.new()
	err = from_file.open_compressed(p_in, File.READ, p_mode)
	if err != OK: 
		return err
	
	var to_file := File.new()
	err = to_file.open(p_out, File.WRITE)
	if err != OK:
		from_file.close()
		return err
	
	var fl:int = from_file.get_len()
	var fp:int = from_file.get_position()
	while fp < fl:
		var left = fl - fp
		if left >= 8192:
			left = 8192
		to_file.store_buffer(from_file.get_buffer(left))
		if p_signal_node != null && p_signal_name != "":
			p_signal_node.emit_signal(p_signal_name, left)
		fp = from_file.get_position()
	
	from_file.close()
	to_file.close()
	
	return err


static func directory_check(p_path: String, p_create: bool = false) -> int:
	var dir := Directory.new()
	var err: int = OK
	if !dir.dir_exists(p_path.get_base_dir()):
		if !p_create:
			print("FileHandler:", "Create folder not enabled!")
			return ERR_INVALID_PARAMETER
		err = dir.make_dir_recursive(p_path.get_base_dir())
	return err


static func file_remove(p_path: String) -> bool:
	var d: Directory = Directory.new()
	var rtn: bool = false
	if d.file_exists(p_path):
		rtn = (d.remove(p_path) == OK)
	return rtn


static func get_compress_ext_type(p_ext: String) -> int:
	var type: int = -1
	match p_ext:
		"lz":
			type = File.COMPRESSION_FASTLZ
		"zip":
			type = File.COMPRESSION_DEFLATE
		"zst":
			type = File.COMPRESSION_ZSTD
		"gz":
			type = File.COMPRESSION_GZIP
		_:
			print("Unrecognized compression method")
	
	return type


static func get_compress_type_ext(p_method: int) -> String:
	var p_ext: String = ""
	match p_method:
		File.COMPRESSION_FASTLZ:
			p_ext = ".lz"
		File.COMPRESSION_DEFLATE:
			p_ext = ".zip"
		File.COMPRESSION_ZSTD:
			p_ext = ".zst"
		File.COMPRESSION_GZIP:
			p_ext = ".gz"
		_:
			print("Unrecognized compression method")
	
	return p_ext


static func get_file_md5(p_path: String) -> String:
	var f := File.new()
	var h: String = f.get_md5(p_path)
	f.close()
	return h


static func get_file_sha256(p_path: String) -> String:
	var f := File.new()
	var h: String = f.get_sha256(p_path)
	f.close()
	return h


static func get_paths(p_start_path: String, p_recurse_dirs: bool = false, 
		p_skip_hidden: bool = true) -> Array:
	var paths: Array = []
	var dirs: Array = []
	var dir := Directory.new()
	var err: int = dir.open(p_start_path)
	if err != OK:
#		print("FileHandler.get_files(), error opening directory!")
		return paths
	err = dir.list_dir_begin(true, p_skip_hidden)
	if err != OK:
		print("FileHandler.get_paths(), error getting directory list!")
		return paths
	
	var fn: String = dir.get_next()
	var working_dir: String = ""
	while (fn != "" || dirs.size() > 0):
#		print("fn:", fn)
#		print("dirs:", dirs)
		if fn != "":
			if dir.current_is_dir():
				if p_recurse_dirs:
					var p: String = working_dir + fn  + "/"
#					print("Adding dir:", p)
					dirs.push_back(p)
			else:
				paths.push_back(working_dir + fn)
		
		if fn == "" && dirs.size() > 0:
			var d: String = dirs.pop_front()
#			print("new dir:", p_path + d)
			err = dir.change_dir(p_start_path + d)
			if err == OK:
#				print("cur dir:", dir.get_current_dir())
				err = dir.list_dir_begin(true, p_skip_hidden)
				if err != OK:
					print("FileHandler.get_files(), error getting directory list!")
					continue
				working_dir = d
			else:
				print("Change Dir error:", err)
		
		fn = dir.get_next()
	
	return paths


static func read_json(p_path: String) -> Dictionary:
	var d: Dictionary = {}
	var f:= File.new()
	if f.file_exists(p_path):
		var e : int = f.open(p_path, File.READ)
		if e == OK:
			d = parse_json(f.get_as_text())
			f.close()
		else:
			print("FileHandler read_json fopen error:", e)
#	else:
#		print("FileHandler read_json not existing path:", p_path)
	return d


static func save_json(p_path: String, p_data: Dictionary, p_create_folder: bool = false) -> int:
	var e: int = directory_check(p_path, p_create_folder)
	if e != OK:
		return e
	var f := File.new()
	e = f.open(p_path, File.WRITE)
	if e:
		print("FileHandler:", "Open file ", p_path, " write failed - ", e)
		return e
	f.store_string(to_json(p_data))
	f.close()
	return OK


static func write_string(p_path: String, p_data: String, p_create_folder: bool = false) -> int:
	var e: int = directory_check(p_path, p_create_folder)
	if e != OK:
		return e
	
	var f = File.new()
	e = f.open(p_path, File.WRITE)
	if e != OK:
		print("FileHandler:", "Open file ", p_path, " write failed - ", e)
		return e
	f.store_string(p_data)
	f.close()
	return OK
