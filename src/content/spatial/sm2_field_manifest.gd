class_name Sm2FieldManifest
extends Resource

@export var version: String = ""
@export var scenario_id: String = ""
@export var seed: int = 0
@export var width: int = 0
@export var height: int = 0
@export var default_surface_id: String = ""
@export var default_elevation: int = 0
@export var surfaces: Array[Sm2SurfaceContent] = []
@export var tiles: Array[Sm2CellOverrideContent] = []
@export var spawns: Array[Sm2SpawnMarkerContent] = []
