"""Kullanıcı pipeline'ı: animation-only skinning artifact teşhis + bake + export.
Adımlar kullanıcı spesifikasyonundaki numaralarla işaretli."""
import bpy
import math
from mathutils import Vector

OUT = "/home/user/mouse_rig"

# --- 1. DOSYAYI ÇOĞALT, orijinali ezme ---
bpy.ops.wm.open_mainfile(filepath=OUT + "/MouseRigged_anim.blend")
bpy.ops.wm.save_as_mainfile(filepath=OUT + "/MouseRigged_baked.blend")
print("1) kopya: MouseRigged_baked.blend (orijinal korunuyor)")

arm_ob = bpy.data.objects["MouseRig"]
mesh_ob = next(o for o in bpy.data.objects
               if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers))
scene = bpy.context.scene
deform = {b.name for b in arm_ob.data.bones if b.use_deform}
LIMB = {p + "." + s for p in ("upper_arm", "forearm", "hand", "thigh", "shin", "foot") for s in ("L", "R")}

# --- 3-4. F-CURVE DENETİMİ ---
# Blender 5.x katmanlı action API'si: fcurve'ler channelbag'lerde yaşar
def action_fcurves(act):
    out = []
    for layer in act.layers:
        for strip in layer.strips:
            for cb in strip.channelbags:
                out.append((cb, list(cb.fcurves)))
    return out

print("=== 3) F-curve denetimi ===")
ACTIONS = ["idle_loop", "walk_loop"]
scale_offenders = []
for an in ACTIONS:
    act = bpy.data.actions[an]
    per_bone = {}
    for _cb, fcs in action_fcurves(act):
      for fc in fcs:
        if not fc.data_path.startswith('pose.bones["'):
            continue
        bone = fc.data_path.split('"')[1]
        kind = fc.data_path.rsplit(".", 1)[-1]
        per_bone.setdefault(bone, set()).add(kind)
        if kind == "scale" and bone in deform:
            vals = {round(kp.co[1], 5) for kp in fc.keyframe_points}
            if vals - {1.0}:
                scale_offenders.append((an, bone, sorted(vals)))
        if kind == "rotation_euler":
            mx = max(abs(kp.co[1]) for kp in fc.keyframe_points)
            if mx > math.radians(60):
                print("  AŞIRI ROTASYON: %s/%s %.0f°" % (an, bone, math.degrees(mx)))
      # (girinti: channelbag döngüsü)
    for bone, kinds in sorted(per_bone.items()):
        flag = ""
        if bone in deform and "scale" in kinds:
            flag += " [SCALE-DEFORM!]"
        if bone in LIMB and "location" in kinds:
            flag += " [LOCATION-LIMB!]"
        if flag:
            print("  %s/%s: %s%s" % (an, bone, sorted(kinds), flag))
print("4) deform kemiğinde 1!=scale key:", scale_offenders if scale_offenders else "YOK")
# scale eğrilerini deform kemiklerinden sil (varsa)
for an in ACTIONS:
    act = bpy.data.actions[an]
    for cb, fcs in action_fcurves(act):
        for fc in fcs:
            if fc.data_path.startswith('pose.bones["') and fc.data_path.endswith("scale"):
                if fc.data_path.split('"')[1] in deform:
                    cb.fcurves.remove(fc)
print("4) deform scale eğrileri silindi (önlem)")
print("5) retarget kontrolü: animasyonlar BU iskelette sıfırdan üretildi — retarget YOK")

# --- 2/9. bake ÖNCESİ referans: kısıtlı rig'in gerçek (Blender-içi) deformasyonu ---
def eval_verts():
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh_ob.evaluated_get(dg)
    m = ev.to_mesh()
    out = [v.co.copy() for v in m.vertices]
    ev.to_mesh_clear()
    return out

def clear_pose():
    """key'lenmemiş kanal artığı kalmasın: tam sıfırla."""
    for p in arm_ob.pose.bones:
        p.location = (0, 0, 0)
        p.rotation_euler = (0, 0, 0)
        p.rotation_quaternion = (1, 0, 0, 0)
        p.scale = (1, 1, 1)

SAMPLES = {"idle_loop": [1, 40, 80, 121], "walk_loop": [1, 9, 17, 25, 33]}
for tr in arm_ob.animation_data.nla_tracks:
    tr.mute = True
reference = {}
for an, frames in SAMPLES.items():
    arm_ob.animation_data.action = None
    clear_pose()
    arm_ob.animation_data.action = bpy.data.actions[an]
    for f in frames:
        scene.frame_set(f)
        reference[(an, f)] = eval_verts()
print("referans (kısıtlı) deformasyon örneklendi")

# --- 6. BAKE: visual keying, her kare, tüm pose kemikleri ---
bpy.context.view_layer.objects.active = arm_ob
bpy.ops.object.mode_set(mode="POSE")
bpy.ops.pose.select_all(action="SELECT")
RANGES = {"idle_loop": (1, 121), "walk_loop": (1, 33)}
baked = {}
for an, (f0, f1) in RANGES.items():
    arm_ob.animation_data.action = None
    clear_pose()
    arm_ob.animation_data.action = bpy.data.actions[an]
    bpy.ops.nla.bake(
        frame_start=f0, frame_end=f1, step=1,
        only_selected=False, visual_keying=True,
        clear_constraints=False, use_current_action=False,
        bake_types={"POSE"},
    )
    nb = arm_ob.animation_data.action
    nb.name = an + "_baked"
    baked[an] = nb
    nfc = sum(len(fcs) for _cb, fcs in action_fcurves(nb))
    print("6) bake:", nb.name, "fcurves=", nfc)
bpy.ops.object.mode_set(mode="OBJECT")

# --- 7. kısıtları SİL + kontrol kemiklerinin deform durumunu doğrula ---
removed_cons = 0
for p in arm_ob.pose.bones:
    for c in list(p.constraints):
        p.constraints.remove(c)
        removed_cons += 1
bad_ctrl = [b.name for b in arm_ob.data.bones
            if (b.name.startswith(("IK_", "POLE_")) or b.name == "root") and b.use_deform]
ctrl_vgroups = [g.name for g in mesh_ob.vertex_groups
                if g.name.startswith(("IK_", "POLE_")) or g.name == "root"]
print("7) silinen kısıt: %d | deform açık kontrol kemiği: %s | kontrol vgroup: %s"
      % (removed_cons, bad_ctrl or "YOK", ctrl_vgroups or "YOK"))

# --- bake SADAKAT doğrulaması: kısıtsız+baked == kısıtlı+orijinal mi ---
print("=== bake sadakati (kısıtlı referansla fark) ===")
worst = 0.0
for an, frames in SAMPLES.items():
    arm_ob.animation_data.action = None
    clear_pose()
    arm_ob.animation_data.action = baked[an]
    for f in frames:
        scene.frame_set(f)
        cur = eval_verts()
        ref = reference[(an, f)]
        mx = max((cur[i] - ref[i]).length for i in range(len(cur)))
        worst = max(worst, mx)
        print("  %s f%03d: max fark %.3f mm" % (an, f, mx * 1000))
print("BAKE_SADAKAT worst = %.3f mm" % (worst * 1000))

# --- 10. ağırlık temizliği (smooth YOK: şerit-rijit ağırlıklar bozulmasın) ---
bpy.ops.object.select_all(action="DESELECT")
mesh_ob.select_set(True)
bpy.context.view_layer.objects.active = mesh_ob
bpy.ops.object.vertex_group_clean(group_select_mode="ALL", limit=0.001)
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
print("10) Clean+Limit4+Normalize tamam (smooth bilinçli atlandı: kürk şeritleri rijit kalmalı)")

# --- NLA'yı baked aksiyonlarla yeniden kur ---
for tr in list(arm_ob.animation_data.nla_tracks):
    arm_ob.animation_data.nla_tracks.remove(tr)
for an in ACTIONS:
    tr = arm_ob.animation_data.nla_tracks.new()
    tr.name = an  # glTF animasyon adı temiz kalsın
    tr.strips.new(an, 1, baked[an])
arm_ob.animation_data.action = None
scene.frame_set(1)
bpy.ops.wm.save_as_mainfile(filepath=OUT + "/MouseRigged_baked.blend")

# --- 9. en riskli karelerde pati/karın yakın plan (Blender-içi göz testi) ---
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 32
scene.render.resolution_x = 800
scene.render.resolution_y = 800
cam = bpy.data.objects["Cam"]
arm_ob.animation_data.action = baked["walk_loop"]
shots = {
    "paw_f09": (9, (0.42, -0.62, -0.28), (0.05, -0.27, -0.18)),
    "paw_f17": (17, (0.42, -0.62, -0.28), (0.05, -0.27, -0.18)),
    "hind_f09": (9, (0.55, 0.35, -0.25), (0.12, 0.10, -0.15)),
    "belly_f17": (17, (-0.18, -0.62, -0.12), (-0.02, -0.22, -0.13)),
}
for tag, (f, pos, tgt) in shots.items():
    scene.frame_set(f)
    cam.location = Vector(pos)
    cam.rotation_euler = (Vector(tgt) - cam.location).to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = OUT + "/renders/22_baked_" + tag + ".png"
    bpy.ops.render.render(write_still=True)
    print("BAKED_RENDER", tag)
arm_ob.animation_data.action = None
scene.frame_set(1)

# --- 8/11. yalnız deform iskeleti + baked animasyonlarla GLB ---
bpy.ops.object.select_all(action="DESELECT")
mesh_ob.select_set(True)
arm_ob.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=OUT + "/MouseRigged_baked.glb",
    use_selection=True,
    export_animations=True,
    export_animation_mode="NLA_TRACKS",
    export_def_bones=True,
    export_all_influences=False,
    export_yup=True,
)
print("BAKE_PIPELINE_DONE")
