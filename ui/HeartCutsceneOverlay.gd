# res://scripts/ui/HeartCutsceneOverlay.gd
extends BaseOverlay
class_name HeartCutsceneOverlay

@onready var panel: Control = $Panel
@onready var fade_rect: ColorRect = $Panel/FadeRect
@onready var vignette: TextureRect = $Panel/Vignette

var _fade_tween: Tween
var _vignette_tween: Tween

func _ready() -> void:
	# Let BaseOverlay apply its editor/runtime visibility rules
	super._ready()

	# Make sure this overlay never steals input
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.focus_mode = Control.FOCUS_NONE
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_rect.focus_mode = Control.FOCUS_NONE
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vignette.focus_mode = Control.FOCUS_NONE

	# CRITICAL: ensure FadeRect can ever become visible
	# If fade_rect.color.a == 0 in the editor, modulate tween won't show anything.
	var c := fade_rect.color
	if c.a <= 0.001:
		fade_rect.color = Color(c.r, c.g, c.b, 1.0)

	# Start fully transparent at runtime (panel may be hidden by BaseOverlay until we show_overlay)
	if not Engine.is_editor_hint():
		_set_alpha(fade_rect, 0.0)
		_set_alpha(vignette, 0.0)

# --- Public API used by HeartRevealDirector ---------------------------------

func fade_to(alpha: float, duration: float) -> void:
	alpha = clamp(alpha, 0.0, 1.0)
	_ensure_open()

	_kill_tween(_fade_tween)
	_fade_tween = create_tween()
	_fade_tween.set_trans(Tween.TRANS_SINE)
	_fade_tween.set_ease(Tween.EASE_IN_OUT)
	_fade_tween.tween_method(func(a): _set_alpha(fade_rect, a), _get_alpha(fade_rect), alpha, duration)
	_fade_tween.finished.connect(_auto_close_if_clear)

func vignette_to(alpha: float, duration: float) -> void:
	alpha = clamp(alpha, 0.0, 1.0)
	_ensure_open()

	_kill_tween(_vignette_tween)
	_vignette_tween = create_tween()
	_vignette_tween.set_trans(Tween.TRANS_SINE)
	_vignette_tween.set_ease(Tween.EASE_IN_OUT)
	_vignette_tween.tween_method(func(a): _set_alpha(vignette, a), _get_alpha(vignette), alpha, duration)
	_vignette_tween.finished.connect(_auto_close_if_clear)

func flash_magic(duration_in: float = 0.12, hold: float = 0.10, duration_out: float = 0.25) -> void:
	vignette_to(0.55, duration_in)
	await get_tree().create_timer(hold).timeout
	vignette_to(0.0, duration_out)

# --- Internals ---------------------------------------------------------------

func _ensure_open() -> void:
	# Use BaseOverlay’s system so it behaves like your other UIs
	if not is_open():
		show_overlay()

func _auto_close_if_clear() -> void:
	# When both are fully transparent, close overlay to keep editor/game tidy
	if _get_alpha(fade_rect) <= 0.001 and _get_alpha(vignette) <= 0.001:
		hide_overlay()

func _kill_tween(t: Tween) -> void:
	if t != null and t.is_running():
		t.kill()

func _set_alpha(c: CanvasItem, a: float) -> void:
	# Ensure visibility stays true while open
	c.visible = true
	var m := c.modulate
	c.modulate = Color(m.r, m.g, m.b, a)

func _get_alpha(c: CanvasItem) -> float:
	return c.modulate.a
