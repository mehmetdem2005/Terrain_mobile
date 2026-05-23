@tool
extends SceneTree

# Unit test for TerrainObjectPlacer (systems/object_placer.gd).
#
# Covers the PURE logic only — build_instance_transform, should_place,
# mesh_label — so it runs under --headless, where the dummy RenderingServer
# does not store MultiMesh instance transforms (place_one's actual buffer
# write is exercised by the visual test render_object_persistence.gd).

const Placer := preload("res://addons/mobile_terrain/systems/object_placer.gd")

var _failed: int = 0


func _init() -> void:
	_test_origin_is_world()
	_test_world_to_local()
	_test_scale_applied()
	_test_scale_clamped()
	_test_no_nan_zero_normal()
	_test_align_to_normal()
	_test_surface_offset()
	_test_should_place()
	_test_mesh_label()
	if _failed == 0:
		print("OBJECT_PLACER_TEST_OK")
		quit(0)
	else:
		printerr("OBJECT_PLACER_TEST_FAILED: %d failure(s)" % _failed)
		quit(1)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failed += 1
		printerr("  FAIL: " + msg)


# Identity MMI transform → the instance origin equals the world hit point.
func _test_origin_is_world() -> void:
	var tf := Placer.build_instance_transform(
		Vector3(5, 3, 7), Vector3.UP, 1.0, false, false, Transform3D.IDENTITY
	)
	_check(tf.origin.is_equal_approx(Vector3(5, 3, 7)), "origin world (got %s)" % tf.origin)


# MMI translated by (10,0,0) → instance local origin is world minus offset.
# This is the bug the old code lacked: placement stays correct when the
# terrain node is not at the world origin.
func _test_world_to_local() -> void:
	var mmi_xform := Transform3D(Basis(), Vector3(10, 0, 0))
	var tf := Placer.build_instance_transform(
		Vector3(5, 3, 7), Vector3.UP, 1.0, false, false, mmi_xform
	)
	_check(tf.origin.is_equal_approx(Vector3(-5, 3, 7)), "world->local origin (got %s)" % tf.origin)


# object_scale applies a uniform scale to the instance basis.
func _test_scale_applied() -> void:
	var tf := Placer.build_instance_transform(
		Vector3.ZERO, Vector3.UP, 0.5, false, false, Transform3D.IDENTITY
	)
	var s := tf.basis.get_scale()
	_check(s.is_equal_approx(Vector3(0.5, 0.5, 0.5)), "scale 0.5 (got %s)" % s)


# C1 hardening: an out-of-range object_scale is clamped to MAX_OBJECT_SCALE so a
# stray scripted/inspector value can't produce a kilometre-wide instance.
func _test_scale_clamped() -> void:
	var tf := Placer.build_instance_transform(
		Vector3.ZERO, Vector3.UP, 1.0e6, false, false, Transform3D.IDENTITY
	)
	var s := tf.basis.get_scale()
	var cap: float = Placer.MAX_OBJECT_SCALE
	_check(s.is_equal_approx(Vector3(cap, cap, cap)), "scale clamped to %s (got %s)" % [cap, s])


# A degenerate (zero) normal must never produce a NaN basis — that was the
# "stretched spike radiating from a point" failure mode.
func _test_no_nan_zero_normal() -> void:
	var tf := Placer.build_instance_transform(
		Vector3(1, 2, 3), Vector3.ZERO, 1.0, true, false, Transform3D.IDENTITY
	)
	var ok := true
	for v: Vector3 in [tf.origin, tf.basis.x, tf.basis.y, tf.basis.z]:
		if is_nan(v.x) or is_nan(v.y) or is_nan(v.z):
			ok = false
	_check(ok, "no NaN with zero normal")


# align_to_normal: the instance up axis matches the surface normal.
func _test_align_to_normal() -> void:
	var n := Vector3(0.3, 0.9, 0.1).normalized()
	var tf := Placer.build_instance_transform(
		Vector3.ZERO, n, 1.0, true, false, Transform3D.IDENTITY
	)
	var up := tf.basis.y.normalized()
	_check(up.is_equal_approx(n), "up aligns to normal (got %s want %s)" % [up, n])


# TKT-016: a centre-pivot mesh (AABB min-y = -2) is lifted by 2 so its bottom
# sits on the surface — fixes objects sinking half below the terrain.
func _test_surface_offset() -> void:
	var tf := Placer.build_instance_transform(
		Vector3.ZERO, Vector3.UP, 1.0, false, false, Transform3D.IDENTITY, -2.0
	)
	_check(tf.origin.is_equal_approx(Vector3(0, 2, 0)), "surface offset lift (got %s)" % tf.origin)


func _test_should_place() -> void:
	_check(
		Placer.should_place(Vector3.INF, Vector3(1, 1, 1), 2.0), "first placement always allowed"
	)
	_check(not Placer.should_place(Vector3.ZERO, Vector3(1, 0, 0), 2.0), "within spacing rejected")
	_check(Placer.should_place(Vector3.ZERO, Vector3(3, 0, 0), 2.0), "beyond spacing allowed")


func _test_mesh_label() -> void:
	var box := BoxMesh.new()
	_check(
		Placer.mesh_label(box) == "BoxMesh",
		"path-less label -> class (got %s)" % Placer.mesh_label(box)
	)
	box.resource_name = "Crate"
	_check(
		Placer.mesh_label(box) == "Crate", "resource_name label (got %s)" % Placer.mesh_label(box)
	)
	_check(Placer.mesh_label(null) == "Object", "null mesh label")
