extends AcceptDialog

signal report_submitted()

@onready var title_input: LineEdit = %TitleInput
@onready var description_input: TextEdit = %DescriptionInput
@onready var category_option: OptionButton = %CategoryOption
@onready var status_label: Label = %StatusLabel
@onready var submit_btn: Button = %SubmitButton

var is_processing: bool = false

# Category options
const CATEGORIES := [
	"General",
	"UI/Interface",
	"Combat",
	"Mining",
	"Trading",
	"Physics/Navigation",
	"Performance",
	"Multiplayer",
	"Other"
]


func _ready() -> void:
	# Setup category dropdown
	for cat in CATEGORIES:
		category_option.add_item(cat)

	# Connect buttons
	submit_btn.pressed.connect(_on_submit)
	canceled.connect(_on_cancel)

	# Setup custom buttons (override default OK button)
	get_ok_button().visible = false
	add_cancel_button("Cancel")


func open_dialog() -> void:
	# Reset form
	title_input.text = ""
	description_input.text = ""
	category_option.selected = 0
	status_label.text = ""
	_set_processing(false)

	popup_centered()
	title_input.grab_focus()


func _on_submit() -> void:
	if is_processing:
		return

	var title: String = title_input.text.strip_edges()
	var description: String = description_input.text.strip_edges()
	var category: String = CATEGORIES[category_option.selected]

	# Validation
	if not _validate_input(title, description):
		return

	# Disable inputs during processing
	_set_processing(true)
	_show_status("Submitting bug report...", Color(0.8, 0.8, 0.8))

	# Get game version (could be from project settings or autoload)
	var game_version := "0.1.0"  # TODO: Get from ProjectSettings or GameState

	# Submit to backend
	var result: Dictionary = await BackendManager.submit_bug_report(title, description, category, game_version)

	if result.get("success", false):
		_show_status("Bug report submitted! Thank you.", Color(0.3, 0.9, 0.3))
		await get_tree().create_timer(1.5).timeout
		report_submitted.emit()
		hide()
	else:
		var error_msg: String = result.get("error", "Failed to submit report")
		_show_status("Error: " + error_msg, Color(0.9, 0.3, 0.3))
		_set_processing(false)


func _validate_input(title: String, description: String) -> bool:
	if title.is_empty():
		_show_status("Title is required", Color(0.9, 0.3, 0.3))
		return false

	if title.length() < 10:
		_show_status("Title must be at least 10 characters", Color(0.9, 0.3, 0.3))
		return false

	if description.is_empty():
		_show_status("Description is required", Color(0.9, 0.3, 0.3))
		return false

	if description.length() < 20:
		_show_status("Description must be at least 20 characters", Color(0.9, 0.3, 0.3))
		return false

	return true


func _set_processing(processing: bool) -> void:
	is_processing = processing
	title_input.editable = not processing
	description_input.editable = not processing
	category_option.disabled = processing
	submit_btn.disabled = processing


func _show_status(message: String, color: Color) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", color)


func _on_cancel() -> void:
	hide()
