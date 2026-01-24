extends BaseOverlay

@export var progress_data: HeartProgressData

@onready var panel: Panel = $Panel
@onready var domains_box: VBoxContainer = $Panel/VBox/Domains
@onready var title_label: Label = $Panel/VBox/Title
@onready var hint_label: Label = $Panel/VBox/Hint

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		return

	title_label.text = "Valley Heart"
	hint_label.text = "Progress grows gently. Sprouts are quick. Roots take time."
	_refresh()

func show_ui() -> void:
	_refresh()
	super.show_overlay()

func hide_ui() -> void:
	super.hide_overlay()

func toggle_ui() -> void:
	if panel.visible:
		hide_ui()
	else:
		show_ui()

func is_open() -> bool:
	return panel.visible

func set_progress_data(d: HeartProgressData) -> void:
	progress_data = d
	_refresh()

func _refresh() -> void:
	if domains_box == null:
		return

	for c in domains_box.get_children():
		c.queue_free()

	if progress_data == null:
		_add_info_row("(No HeartProgressData assigned yet.)")
		return

	for domain in progress_data.domains:
		_add_domain_row(domain)

func _add_info_row(text: String) -> void:
	var l := Label.new()
	l.text = text
	domains_box.add_child(l)

func _add_domain_row(domain: HeartDomainData) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)

	var header := Label.new()
	header.text = domain.display_name if domain.display_name.strip_edges() != "" else domain.id
	row.add_child(header)

	var sprouts_line := Label.new()
	sprouts_line.text = "Sprouts: %d / %d" % [domain.sprouts_done, domain.sprouts_total]
	row.add_child(sprouts_line)

	var sprouts_bar := ProgressBar.new()
	sprouts_bar.min_value = 0
	sprouts_bar.max_value = max(1, domain.sprouts_total)
	sprouts_bar.value = domain.sprouts_done
	row.add_child(sprouts_bar)

	var roots_line := Label.new()
	roots_line.text = "Roots: %d / %d" % [domain.roots_done, domain.roots_total]
	row.add_child(roots_line)

	var roots_bar := ProgressBar.new()
	roots_bar.min_value = 0
	roots_bar.max_value = max(1, domain.roots_total)
	roots_bar.value = domain.roots_done
	row.add_child(roots_bar)

	var hint_line := Label.new()
	hint_line.text = "Next: " + domain.next_hint
	hint_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(hint_line)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	row.add_child(spacer)

	domains_box.add_child(row)
