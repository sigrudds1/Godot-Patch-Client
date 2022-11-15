extends Popup


func _on_Ok_btn_button_up() -> void:
	queue_free()


func set_text(p_text: String) -> void:
	$RichTextLabel.text = p_text
