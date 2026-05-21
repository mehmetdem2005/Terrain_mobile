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
# This Resource subclass lets the user externalize that data into a
# binary .res alongside the scene. The .tscn then only stores a
# string path, and Godot's resource loader handles the heavy lifting
# (memory-mapped reads, dedupe across nodes referencing the same .res,
# etc.). For small maps the inline path is still the default; opt-in
# via the "click_to_externalize" inspector toggle.
#
# Schema:
#   - height_data: PackedFloat32Array, length map_size² (row-major)
#   - map_size: the dimension this snapshot was taken at; sanity-check
#     against the parent node's map_size at load time
#   - splatmap_bytes: raw RGBA8 bytes, length splatmap_size² × 4
#   - splatmap_size: dimension of the splatmap (usually equals map_size)
#
# Both arrays default to empty so a freshly-created MobileTerrainData
# resource is in a known-safe state and the load path can detect
# "no data yet" cheaply with .size() == 0.

@export var height_data: PackedFloat32Array
@export var map_size: int = 0
@export var splatmap_bytes: PackedByteArray
@export var splatmap_size: int = 0
