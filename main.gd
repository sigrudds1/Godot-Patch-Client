extends Control
#TODO - Report errors to UI
#TODO - OSX - Launch game, find game process, can a terminal be opened for debug?
#TODO - Check if threads are locked?
#TODO - Change button icon?

# warning-ignore:unused_signal
signal downloaded(bytes)
# warning-ignore:unused_signal
signal decompressed(bytes)
# warning-ignore:unused_signal
signal warned(msgs)
# warning-ignore:unused_signal
signal errored(msg)


#const kOSes: Array = ["none", "Windows", "X11", "OSX"]
const kOSes: Array = ["none", "Windows", "X11"]
const kGameExes: Array = ["", "LauncherTestGame.exe", "LauncherTestGame.x86_64", "LauncherTestGame.app"]
const kCheckSrvr_SEC: float = 60.0

#TODO Get max ping over 10 tries then x2 as packet time
const kConnTimeout_MS: int = 2000
const kConnTimeout_SEC: float = 2.0

#public
var _state: int = Glb.STATE_IDLE setget _noset
#var _url: String = "192.168.2.230"
var _url: String = "localhost"
var _port: int = 4242
var _dl_byte_total: int = 0 setget _noset
var _dl_bytes: int = 0 setget _noset
var _decompressed_bytes: int = 0 setget _noset

#private
var _game_folder_: String = "Game/" setget _noset
var _game_exe_: String = "" setget _noset
var _game_manifest_: Dictionary = {} setget _noset
var _launcher_manifest_: Dictionary = {} setget _noset
var _launcher_updated_: bool = false setget _noset

var _manifest_thread_: Thread = Thread.new() setget _noset
var _manifest_sema_: Semaphore = Semaphore.new() setget _noset
var _manifest_busy_: bool = false

var _proc_time_sec_: float = 0.0 setget _noset

var _tcp_peer_: StreamPeerTCP setget _noset
var _connect_thread_: Thread setget _noset
var _downloading_: bool = false setget _noset

var _update_thread_: Thread = Thread.new() setget _noset

var _decompress_thread_: Thread = Thread.new() setget _noset
var _decompress_sema_: Semaphore = Semaphore.new() setget _noset
var _decompress_list_: Array = [] setget _noset
var _decompressing_: bool = false setget _noset

var _game_name_: String = "Test Game" setget _noset
var _game_path_: String = "" setget _noset
var _game_update_ok_: bool = false
var _game_running_thr_: Thread = Thread.new() setget _noset
var _game_running_sema_: Semaphore = Semaphore.new() setget _noset
var _game_running_tmr: float = 1.0
var _is_game_running_: bool = true


func _noset(_void) -> void:
	pass


func _exit_tree() -> void:
	_state = Glb.STATE_EXIT
# warning-ignore:return_value_discarded
	_decompress_sema_.post()
# warning-ignore:return_value_discarded
	_manifest_sema_.post()
# warning-ignore:return_value_discarded
	_game_running_sema_.post()
	m_thread_finished(_connect_thread_)
	m_thread_finished(_decompress_thread_)
	m_thread_finished(_manifest_thread_)
	m_thread_finished(_update_thread_)
	m_thread_finished(_game_running_thr_)


func _ready() -> void:
	$StartButton.text = "Checking Files"
	$StartButton.disabled = true
	
	_game_exe_ =  kGameExes[kOSes.find(Glb.os_name)]
	_game_path_= Glb.exe_dir + _game_folder_ + _game_exe_
	
	var err: int = _decompress_thread_.start(self, "m_decompress_thr", _decompress_thread_)
	if err != OK:
		printerr("Decompress thread ERR:", err)
	
	err = _manifest_thread_.start(self, "m_manifest_thr", _manifest_thread_)
	if err != OK:
		printerr("Decompress thread ERR:", err)
	
	err = _game_running_thr_.start(self, "m_game_running_thr")
	if err != OK:
		printerr("Game Running thread ERR:", err)
	
	err = connect("downloaded", self, "_on_data_downloaded")
	if err != OK:
		printerr("Main._ready() - error connecting download signal")
	err = connect("decompressed", self, "_on_decompressed")
	if err != OK:
		printerr("Main._ready() - error connecting decompressed signal")
	err = connect("warned", self, "_on_warning")
	if err != OK:
		printerr("Main._ready() - error connecting warned signal")
		
	if Glb.os_name == "X11" && OS.is_debug_build():
		#Is gnome_terminal installed, most pupular Linux distros have it
		var out: Array = []
# warning-ignore:return_value_discarded
		OS.execute("whereis", ["gnome-terminal"], true, out)
		if out[0].get_slice(":", 1).strip_edges() == "":
			emit_signal("warned", str("Warning gnome-terminal is not " +  
						"installed, please install for stability"))
	
# warning-ignore:return_value_discarded
	_manifest_sema_.post()
# warning-ignore:return_value_discarded
	_game_running_sema_.post()

	_state = Glb.STATE_UPDATE_LAUNCHER
	_proc_time_sec_ = 0


func _physics_process(p_delta: float) -> void:
	if _decompress_list_.size() > 0 && !_decompressing_:
		_decompressing_ = true
# warning-ignore:return_value_discarded
		_decompress_sema_.post()
		if _state == Glb.STATE_UPDATE_LAUNCHER:
			_launcher_updated_ = true
	
	if _downloading_ || _manifest_busy_:
		return
	
	if _launcher_updated_:
		if _decompress_list_.size() > 0 || _decompressing_:
			return
		else:
			m_reload_launcher()
			return
	
	_proc_time_sec_ += p_delta
	_game_running_tmr += p_delta
	
	match _state:
		Glb.STATE_IDLE:
			if _proc_time_sec_ > kCheckSrvr_SEC:
				if !_decompressing_:
					$StartButton.text = "Checking Files"
					$StartButton.disabled = true
					_state = Glb.STATE_UPDATE_LAUNCHER
# warning-ignore:return_value_discarded
					_manifest_sema_.post()
					_proc_time_sec_ = 0
				return
		Glb.STATE_RETRY:
			if _proc_time_sec_ > kConnTimeout_SEC:
				_state = Glb.STATE_UPDATE_LAUNCHER
				_proc_time_sec_ = 0
				return
		Glb.STATE_UPDATE_LAUNCHER:
			if _manifest_busy_:
				_proc_time_sec_ = 0
				return
			if m_update_start() == ERR_CANT_CREATE:
				_tcp_peer_ = Net.tcp_disconnect(_tcp_peer_)
				_state = Glb.STATE_RETRY
				_proc_time_sec_ = 0
			else:
				_proc_time_sec_ = 0
		Glb.STATE_UPDATE_GAME:
			if _manifest_busy_:
				_proc_time_sec_ = 0
				return
			if _game_running_tmr > 1.0:
				_game_running_tmr = 0.0
# warning-ignore:return_value_discarded
				_game_running_sema_.post()
			if _is_game_running_:
				_state = Glb.STATE_IDLE
				_proc_time_sec_ = 0
				return
			if m_update_start() == ERR_CANT_CREATE:
				_tcp_peer_ = Net.tcp_disconnect(_tcp_peer_)
				_state = Glb.STATE_RETRY
				_proc_time_sec_ = 0
		Glb.STATE_WAITING:
			if _game_update_ok_:
				_state = Glb.STATE_UPDATE_GAME
			else:
				$StartButton.text = "Update" 
				$StartButton.disabled = false
				if _proc_time_sec_ > kCheckSrvr_SEC:
					_state = Glb.STATE_IDLE
					_proc_time_sec_ = 0
		Glb.STATE_START_GAME:
			if _proc_time_sec_ > kCheckSrvr_SEC:
				_state = Glb.STATE_IDLE
			if _game_running_tmr > 1.0:
				_game_running_tmr = 0.0
# warning-ignore:return_value_discarded
				_game_running_sema_.post()
			if _is_game_running_:
				$StartButton.text = "Running"
				$StartButton.disabled = true
			else:
				$StartButton.text = "Play"
				$StartButton.disabled = false
		_:
			pass
	
	if _tcp_peer_ == null:
		return
	elif (_proc_time_sec_ > kConnTimeout_SEC && 
			_tcp_peer_.get_status() == StreamPeerTCP.STATUS_CONNECTED):
		_tcp_peer_ = Net.tcp_disconnect(_tcp_peer_)
		_state = Glb.STATE_IDLE
		_proc_time_sec_ = 0


func _on_data_downloaded(p_bytes: int) -> void:
	_dl_bytes += p_bytes
	var ratio: float = 0.0
	if _dl_byte_total > 0:
		ratio = float(_dl_bytes) / float(_dl_byte_total)
	$DownloadProgress.value = ratio


func _on_decompressed(p_bytes: int) -> void:
	_decompressed_bytes += p_bytes
	var ratio: float = 0.0
	if _dl_byte_total > 0:
		ratio = float(_decompressed_bytes) / float(_dl_byte_total)
	$DecompressProgress.value = ratio


func _on_StartButton_button_up() -> void:
	$StartButton.disabled = true
	if _state == Glb.STATE_WAITING:
		_game_update_ok_ = true
		return
	
	#TODO do MacOS
	if Glb.os_name == "OSX":
		emit_signal("errored", str("MacOS build not currently available!"))
		return
	
	if OS.is_debug_build():
		if Glb.os_name == "X11":
			var x11_args := Array(["--title=" + _game_exe_.get_basename() + " Debug", "--", _game_path_])
# warning-ignore:return_value_discarded
			OS.execute("gnome-terminal", x11_args, false)
		elif Glb.os_name == "Windows":
# warning-ignore:return_value_discarded
			OS.execute("CMD.exe", ["/C", _game_path_], false, [], false, true)
		elif Glb.os_name == "OSX":
			pass
	else:
# warning-ignore:return_value_discarded
		OS.execute(_game_path_, [], false)
# warning-ignore:return_value_discarded
	_game_running_sema_.post()


func _on_warning(p_msg: String) -> void:
	var new_popup = load("res://Scenes/UI/Alert.tscn").instance()
	add_child(new_popup, true)
	new_popup.set_text(p_msg)
	new_popup.show()


func m_decompress_thr(p_this_thread: Thread) -> void:
	while _state < Glb.STATE_EXIT:
		if _decompress_sema_.wait() != OK:
			printerr("Main.m_decompress_thr() semephore busy")
		if _state == Glb.STATE_EXIT:
			break
		_decompressing_ = true
		if _decompress_list_.size() > 0:
			var d: Dictionary = _decompress_list_.pop_front()
			var to_path: String = d.file.trim_suffix(".tmp")
			$DecompressFileName.text = "Extracting " + to_path.get_file()
			if !FileTool.decompress_file(d.file, to_path, d.type, self, 
					"decompressed") == OK:
				printerr("Main.m_decompress_thr() decompress_file err:", d.file)
			if !FileTool.file_remove(d.file):
				printerr("Main.m_decompress_thr() not file_remove:", d.file)
			if _decompress_list_.size() <= 0:
				_manifest_busy_ = true
# warning-ignore:return_value_discarded
				_manifest_sema_.post()
		
		if _downloading_:
			$DecompressFileName.text = "Waiting..."
		else:
			$DecompressFileName.text = ""
			
		_decompressing_ = false
	call_deferred("m_thread_finished", p_this_thread)


func m_dl() -> void:
	_downloading_ = true
	_tcp_peer_.put_var({
			"func": Glb.FUNC_TOTAL_BYTES,
			"status": Glb.STATUS_CONT
			})
	var idle_tm: int = Time.get_ticks_msec() + kConnTimeout_MS
	var max_pkt_tm: int = kConnTimeout_MS >> 1
	
	while Time.get_ticks_msec() < idle_tm:
		var d: Dictionary = Net.get_dict_data(_tcp_peer_, kConnTimeout_MS)
		if d.has_all(["type", "file", "size"]):
			_tcp_peer_.put_var({
				"func": Glb.FUNC_SEND_FILE,
				"status": Glb.STATUS_CONT
				})
			idle_tm = Time.get_ticks_msec() + kConnTimeout_MS
			#server sends the file in bytes from the compressed file as compressed
			# save as tmp compressed then decompress in another thread
			var fp: String = Glb.exe_dir + d.file + ".tmp"
			if FileTool.directory_check(fp, true):
				printerr("Main.m_dl() can't write path:", fp)
				_tcp_peer_.put_var({
					"func": Glb.FUNC_SEND_FILE,
					"error": ERR_FILE_CANT_WRITE
					})
				continue
			
			$DownloadFileName.text = "Downloading " + d.file.get_file()
			$StartButton.text = "Downloading"
			$StartButton.disabled = true
			
			var dl_bytes: int = Net.tcp_rcv_file(_tcp_peer_, fp, max_pkt_tm, 
				self, "downloaded")
			if dl_bytes != d.size:
				printerr("Main.m_dl() - download size mismatch expected:", 
					d.size, " got:", dl_bytes)
				_tcp_peer_.put_var({
					"func": Glb.FUNC_SEND_FILE,
					"error": ERR_INVALID_DATA
					})
			else:
				_decompress_list_.push_back({"file": fp, "type": d.type})
				_tcp_peer_.put_var({
					"func": Glb.FUNC_SEND_FILE,
					"status": Glb.STATUS_NEXT
					})
				idle_tm = Time.get_ticks_msec() + kConnTimeout_MS
		else:
			if !Utils.dict_has_key_val({
					"func": Glb.FUNC_TOTAL_BYTES,
					"status": Glb.STATUS_DONE}):
				prints("Main.m_dl() - Unexpected server data:", d)
				_tcp_peer_.put_var({
					"func": Glb.FUNC_SEND_FILE,
					"error": ERR_INVALID_PARAMETER
					})
			else:
				$DownloadFileName.text = "Update Done"
				_tcp_peer_.put_var({
					"func": Glb.FUNC_SEND_FILE,
					"status": Glb.STATUS_DONE
					})
			break
	
	_downloading_ = false


func m_game_running_thr(_void) -> void:
	var out: Array = []
	while _state < Glb.STATE_EXIT:
# warning-ignore:return_value_discarded
		_game_running_sema_.wait()
		if Glb.os_name == "X11":
# warning-ignore:return_value_discarded
			OS.execute("ps", ["auxww"], true, out)
			_is_game_running_ =  out[0].find(_game_path_) >  -1
		elif Glb.os_name == "Windows":
	# warning-ignore:return_value_discarded
			OS.execute("CMD.exe", ["/C", "wmic process get ExecutablePath"], true, out)
			_is_game_running_ =  out[0].find(_game_path_) >  -1
		elif Glb.os_name == "OSX":
			printerr("OSX not supported")
			_is_game_running_ = false
		else:
			printerr("No OS found")
			_is_game_running_ = false


func m_is_srvr_conn() -> bool:
	if _tcp_peer_ == null:
		return false
	return _tcp_peer_.get_status() == StreamPeerTCP.STATUS_CONNECTED


func m_manifest_thr(p_this_thread: Thread) -> void:
	#Note - Can update everything but the launcher exe, workaround is to
	# download and execute a separate temp launcher.exe to update the 
	# launcher.exe and then execute the new updated launcher.exe
	# I think you could also run a force command to overwite running executed file?
	
	while _state < Glb.STATE_EXIT:
		if _manifest_sema_.wait() != OK:
			printerr("Main.m_manifest_thr() semephore busy")
		if _state == Glb.STATE_EXIT:
			break
		_manifest_busy_ = true
		_game_manifest_ = {}
		_launcher_manifest_ = {}
		#First all the files/folders, in the main folder
		var files: Array = FileTool.get_paths(Glb.exe_dir, true)
		for f in files:
			if f.begins_with(_game_folder_):
				_game_manifest_[f] = {}
				_game_manifest_[f]["md5hash"] = FileTool.get_file_md5(Glb.exe_dir + f)
			elif f.begins_with("AddOns/"): #Folder exlusion example
				pass
			else: #The rest are launcher folders/files
				_launcher_manifest_[f] = {}
				_launcher_manifest_[f]["md5hash"] = FileTool.get_file_md5(Glb.exe_dir + f)
		
		_manifest_busy_ = false
	
	call_deferred("m_thread_finished", p_this_thread)


func m_reload_launcher() -> void:
	if _downloading_ || _decompressing_ || _decompress_list_.size() > 0:
		return
	set_process(false)
	Glb.update_pck()
# warning-ignore:return_value_discarded
	get_tree().reload_current_scene()


func m_srvr_conn() -> int:
	$StartButton.text = "Connecting"
	$StartButton.disabled = true
	_tcp_peer_ = Net.tcp_disconnect(_tcp_peer_)
	_tcp_peer_ = Net.tcp_connect(_url, _port, kConnTimeout_MS)
	if _tcp_peer_ ==  null:
		return ERR_CANT_CONNECT
	else:
		return ERR_CANT_CONNECT


func m_srvr_conn_thr(p_this_thread: Thread) -> void:
	_tcp_peer_ = Net.tcp_disconnect(_tcp_peer_)
	_tcp_peer_ = Net.tcp_connect(_url, _port, kConnTimeout_MS)
	call_deferred("m_thread_finished", p_this_thread)


func m_thread_finished(p_thread: Thread) -> void:
	if p_thread != null:
		if p_thread.is_active():
			p_thread.wait_to_finish() 


func m_update_start() -> int:
	$StartButton.text = "Updating"
	$StartButton.disabled = true
	if _update_thread_ == null:
		_update_thread_ = Thread.new()
	if _update_thread_.is_active():
		return ERR_BUSY
	var err: int = _update_thread_.start(self, "m_update_thr", _update_thread_)
	if err != OK:
		printerr("Update thread ERR_CANT_CREATE:")
	return err


func m_update_thr(p_this_thread: Thread) -> void:
	if !m_is_srvr_conn():
		if m_srvr_conn() != OK:
			_state = Glb.STATE_RETRY
			_proc_time_sec_ = 0
			call_deferred("m_thread_finished", p_this_thread)
			return
	
	var out: Dictionary = {
			"func": Glb.FUNC_UPDATE_LAUNCHER,
			"os": Glb.os_name,
			"manifest": _launcher_manifest_
			}
	if _state == Glb.STATE_UPDATE_LAUNCHER:
		pass
	elif _state == Glb.STATE_UPDATE_GAME:
		out["func"] = Glb.FUNC_UPDATE_GAME
		out["manifest"] = _game_manifest_
	else:
		out["func"] = Glb.FUNC_QUIT
	if m_is_srvr_conn():
		_tcp_peer_.put_var(out)
		
		var d: Dictionary = Net.get_dict_data(_tcp_peer_, kConnTimeout_MS)
		if Utils.dict_has_key_val(d, {"func": Glb.FUNC_TOTAL_BYTES, 
				"total_bytes": null}):
			_dl_byte_total = d.total_bytes
			_dl_bytes = 0
			_decompressed_bytes = 0
			if _state == Glb.STATE_UPDATE_LAUNCHER:
				m_dl()
			elif _state == Glb.STATE_UPDATE_GAME:
				if _game_update_ok_:
					m_dl()
				else:
					out["func"] = Glb.FUNC_TOTAL_BYTES
					out["status"] = Glb.STATUS_DONE
					_tcp_peer_.put_var(out)
					_state = Glb.STATE_WAITING
		elif Utils.dict_has_key_val(d, {"func": Glb.FUNC_TOTAL_BYTES, 
				"status": Glb.STATUS_DONE}):
			if _state == Glb.STATE_UPDATE_LAUNCHER:
				_state = Glb.STATE_UPDATE_GAME
			elif _state == Glb.STATE_UPDATE_GAME:
				_state = Glb.STATE_START_GAME
				_game_update_ok_ = true
		else:
			_tcp_peer_ = Net.tcp_disconnect(_tcp_peer_)
			_state = Glb.STATE_RETRY
			_proc_time_sec_ = 0
	
	if out["func"] == Glb.FUNC_QUIT:
		_state = Glb.STATE_IDLE
		_proc_time_sec_ = 0
	
	call_deferred("m_thread_finished", p_this_thread)
