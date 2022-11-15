class_name Utils extends Node


static func copy_dict_key(p_from: Dictionary, p_to: Dictionary, p_key: String) -> Dictionary:
	if p_from.has(p_key):
		p_to[p_key] = p_from[p_key]
	else:
		p_to = {}
	return p_to


static func dict_has_key_val(p_dict: Dictionary, p_key_val := Dictionary()) -> bool:
	var has: bool = true
	var keys: Array = p_key_val.keys()
	for k in keys:
		has = has && p_dict.has(k)
		if has:
			has = has && (p_dict[k] == p_key_val[k] || p_key_val[k] == null)
		if !has:
			break
	return has


static func thread_array_clean(thr_arr:Array, thr_arr_mutex:Mutex) -> void:
	thr_arr_mutex.lock()
	for idx in range(thr_arr.size() - 1, -1, -1):
		if thr_arr[idx] != null:
			if !thr_arr[idx].is_alive():
				thread_finished(thr_arr[idx])
				thr_arr.remove(idx)
		else:
			thr_arr.remove(idx)
	thr_arr_mutex.unlock()


static func thread_array_finished(thr_arr:Array, thr_inst_id:int, mutex:Mutex) -> void:
	mutex.lock()
	for thr in thr_arr:
#		print("thr.get_instance_id():", thr.get_instance_id())
		if thr.get_instance_id() == thr_inst_id:
			thread_finished(thr)
	mutex.unlock()
	thread_array_clean(thr_arr, mutex)


static func thread_finished(thr: Thread) -> void:
	if thr == null: return
	var delay: int = OS.get_ticks_msec() + 1000
	while thr.is_alive():
		if OS.get_ticks_msec() > delay:
			delay = OS.get_ticks_msec() + 1000
			print("Thread still alive thr:", thr)
	if thr.is_active():
		thr.wait_to_finish()

