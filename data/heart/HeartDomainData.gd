extends Resource
class_name HeartDomainData

@export var id: String = "land"                # unique key (land/sea/people/etc)
@export var display_name: String = "Verdant Heart"

@export var sprouts_done: int = 0
@export var sprouts_total: int = 8

@export var roots_done: int = 0
@export var roots_total: int = 5

@export var stage: int = 0                     # optional “visual stage”
@export var next_hint: String = ""
