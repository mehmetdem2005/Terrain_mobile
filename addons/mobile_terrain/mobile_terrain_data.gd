@tool
class_name MobileTerrainData
extends Resource

# V21: external storage container for MobileTerrain3D's heavy data.
#
# Why: at large map sizes (>= 512×512), inlining height_data and the
# splatmap into the .tscn file produces multi-megabyte scene files
# that load slowly, diff badly in git, and cost full reserialisation
# on every scene save.
#
# This Resource subclass holds the terrain's heavy data in a binary .res
# under res://terrain_data/ (TKT-011). The .tscn only stores the path
# string in MobileTerrain3D.external_data_path; Godot's resource loader does
# the heavy lifting (memory-mapped reads, dedupe across referencing nodes).
#
# Schema:
#   - height_data: PackedFloat32Array, length map_size² (row-major)
#   - map_size: the dimension this snapshot was taken at; sanity-checked
#     against the parent node's map_size at load time
#   - splatmap_bytes: raw RGBA8 bytes, length splatmap_size² × 4
#   - splatmap_size: dimension of the splatmap (usually equals map_size)
#   - object_slots: TKT-011 PR-2 — placed foliage/objects. One entry per
#     MultiMesh: { "mesh_path": String, "transforms": Array[Transform3D] }.
#     Persists objects in the .res instead of baking MultiMeshInstance3D
#     nodes into the .tscn (which lost them whenever the scene save failed).
#
# Arrays default to empty so a fresh resource is in a known-safe state and
# the load path can detect "no data yet" cheaply with .size() == 0.

@export var height_data: PackedFloat32Array
@export var map_size: int = 0
@export var splatmap_bytes: PackedByteArray
@export var splatmap_size: int = 0
@export var object_slots: Array = []
