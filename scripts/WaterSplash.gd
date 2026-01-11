extends Node2D

@export var lifetime: float = 0.6

func _ready() -> void:
	var p := $GPUParticles2D
	p.visible = true
	if p:
		p.restart()
		p.emitting = true

	await get_tree().create_timer(lifetime).timeout
	queue_free()
