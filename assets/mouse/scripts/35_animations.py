"""Seamless döngülü animasyonlar: idle_loop (120f) + walk_loop (32f).

Dikişsizlik garantisi: her kanal periyodu kare aralığını TAM bölen
sin/cos veya periyodik gait fonksiyonlarından örneklenir; kare 1 ve
kare N+1 değer + türev olarak özdeştir.
"""
import bpy
import math
from mathutils import Vector

OUT = "/home/user/mouse_rig"
bpy.ops.wm.open_mainfile(filepath=OUT + "/MouseRigged_clean.blend")

arm_ob = bpy.data.objects["MouseRig"]
mesh_ob = next(o for o in bpy.data.objects
               if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers))
scene = bpy.context.scene
scene.render.fps = 24

bpy.context.view_layer.objects.active = arm_ob
bpy.ops.object.mode_set(mode="POSE")
pb = arm_ob.pose.bones
for p in pb:
    p.rotation_mode = "XYZ"

D = math.radians
ROT_LOCAL = {b.name: arm_ob.data.bones[b.name].matrix_local.to_3x3() for b in arm_ob.data.bones}

def loc_local(bone, world_delta):
    return ROT_LOCAL[bone].transposed() @ Vector(world_delta)

def clear_pose():
    for p in pb:
        p.location = (0, 0, 0)
        p.rotation_euler = (0, 0, 0)
        p.scale = (1, 1, 1)

def key_rot(bone, f, rot):
    pb[bone].rotation_euler = rot
    pb[bone].keyframe_insert("rotation_euler", frame=f)

def key_loc(bone, f, world_delta):
    pb[bone].location = loc_local(bone, world_delta)
    pb[bone].keyframe_insert("location", frame=f)

def new_action(name):
    act = bpy.data.actions.new(name)
    if arm_ob.animation_data is None:
        arm_ob.animation_data_create()
    arm_ob.animation_data.action = act
    return act

def stash(act, start=1):
    tr = arm_ob.animation_data.nla_tracks.new()
    tr.name = act.name
    tr.strips.new(act.name, start, act)
    arm_ob.animation_data.action = None

# ============================== IDLE (120 kare) ==============================
F_IDLE = 120
clear_pose()
act = new_action("idle_loop")
TWO = 2 * math.pi

def pulse(ph, center, width):
    """periyodik yumuşak darbe: merkez fazda 1, dışında 0 (C1 sürekli)."""
    d = (ph - center) % 1.0
    if d > 0.5:
        d -= 1.0
    if abs(d) > width:
        return 0.0
    return math.cos(d / width * math.pi / 2) ** 2

for f in range(1, F_IDLE + 2, 3):
    ph = (f - 1) / float(F_IDLE)          # 0..1 (kare 121 -> ph=1 == ph=0)
    breath = math.sin(TWO * 2 * ph)        # 2 nefes / döngü
    key_rot("spine.02", f, (D(1.1) * breath, 0, 0))
    key_rot("spine.03", f, (D(0.8) * breath, 0, 0))
    # bas: yumusak periyodik bakınma (tam periyot)
    key_rot("head", f, (D(2.0) * math.sin(TWO * 2 * ph + 1.3),
                        0,
                        D(16) * math.sin(TWO * ph)))
    # burun koklama: iki kısa periyodik darbe
    sniff = pulse(ph, 0.30, 0.06) + pulse(ph, 0.36, 0.06) + pulse(ph, 0.78, 0.06)
    key_rot("snout", f, (D(-7) * sniff, 0, 0))
    # kulak seyirmeleri (periyodik darbeler, iki kulak farklı fazda)
    key_rot("ear.R", f, (D(-15) * pulse(ph, 0.25, 0.05), 0, 0))
    key_rot("ear.L", f, (D(-13) * pulse(ph, 0.70, 0.05), 0, 0))
    # kuyruk: faz kaymalı yumuşak salınım
    for i in range(1, 9):
        amp = 1.5 + i * 0.9
        key_rot("tail.%02d" % i, f, (0, 0, D(amp) * math.sin(TWO * ph + i * 0.55)))
print("IDLE keyed")
stash(act)

# ============================== WALK (32 kare) ==============================
F_WALK = 32
clear_pose()
act = new_action("walk_loop")

STRIDE = 0.085   # adım uzunluğu (gövde sabit, yerinde yürüyüş)
LIFT = 0.020     # pati kalkış yüksekliği
DUTY = 0.60      # yere basma oranı
# çapraz yürüyüş fazları: sol-arka + sağ-ön birlikte
PHASE = {"IK_foot.L": 0.00, "IK_hand.R": 0.08, "IK_foot.R": 0.50, "IK_hand.L": 0.58}

def gait(ph):
    """(y_offset, z_offset): stance'ta yerde geriye kayar, swing'te havadan öne döner."""
    ph %= 1.0
    if ph < DUTY:                       # stance: -S/2 (önde) -> +S/2 (arkada), yerde
        t = ph / DUTY
        return (-STRIDE / 2 + t * STRIDE, 0.0)
    t = (ph - DUTY) / (1.0 - DUTY)      # swing: arkadan öne, sinüs kavisle
    y = STRIDE / 2 - t * STRIDE
    return (y, LIFT * math.sin(math.pi * t))

for f in range(1, F_WALK + 2):
    ph = (f - 1) / float(F_WALK)
    for ctrl, off in PHASE.items():
        y, z = gait(ph + off)
        key_loc(ctrl, f, (0, y, z))
    # gövde: adım başına 2 kez hafif iniş-kalkış + minik yalpa
    key_loc("spine.01", f, (0.0025 * math.sin(TWO * ph), 0, -0.004 + 0.004 * math.cos(2 * TWO * ph)))
    key_rot("spine.02", f, (D(1.2) * math.cos(2 * TWO * ph), 0, D(1.5) * math.sin(TWO * ph)))
    key_rot("spine.03", f, (D(0.8) * math.cos(2 * TWO * ph + 0.6), 0, D(-1.2) * math.sin(TWO * ph)))
    # baş: gövde yalpasını dengeler
    key_rot("head", f, (D(-1.0) * math.cos(2 * TWO * ph), 0, D(-1.5) * math.sin(TWO * ph)))
    # kuyruk: yürüyüşe karşı-salınım, faz zinciri
    for i in range(1, 9):
        amp = 2.0 + i * 1.1
        key_rot("tail.%02d" % i, f, (0, 0, D(amp) * math.sin(TWO * ph + math.pi + i * 0.5)))
print("WALK keyed")
stash(act, start=1)

bpy.ops.object.mode_set(mode="OBJECT")
clear_done = True
bpy.ops.wm.save_as_mainfile(filepath=OUT + "/MouseRigged_anim.blend")

# ---------- SEAM TESTİ: kare 1 ve kare N+1 evaluated vertex karşılaştırma ----------
def eval_verts():
    dg = bpy.context.evaluated_depsgraph_get()
    ev = mesh_ob.evaluated_get(dg)
    m = ev.to_mesh()
    out = [v.co.copy() for v in m.vertices]
    ev.to_mesh_clear()
    return out

for nm, F in (("idle_loop", F_IDLE), ("walk_loop", F_WALK)):
    arm_ob.animation_data.action = bpy.data.actions[nm]
    scene.frame_set(1)
    a = eval_verts()
    scene.frame_set(F + 1)
    b = eval_verts()
    mx = max((a[i] - b[i]).length for i in range(len(a)))
    print("SEAM %-10s kare1 vs kare%d: max fark = %.4f mm" % (nm, F + 1, mx * 1000))
arm_ob.animation_data.action = None

# ---------- doğrulama render'ları ----------
scene.render.engine = "CYCLES"
scene.cycles.device = "CPU"
scene.cycles.samples = 32
scene.render.resolution_x = 800
scene.render.resolution_y = 800
cam = bpy.data.objects["Cam"]
cam.location = Vector((0.95, -0.8, 0.45)) * 1.05
cam.rotation_euler = (Vector((0, 0, -0.05)) - cam.location).to_track_quat("-Z", "Y").to_euler()

arm_ob.animation_data.action = bpy.data.actions["walk_loop"]
for f in (1, 9, 17, 25):
    scene.frame_set(f)
    scene.render.filepath = OUT + "/renders/20_walk_f%02d.png" % f
    bpy.ops.render.render(write_still=True)
    print("WALK_RENDER", f)
arm_ob.animation_data.action = bpy.data.actions["idle_loop"]
for f in (30, 85):
    scene.frame_set(f)
    scene.render.filepath = OUT + "/renders/20_idle_f%03d.png" % f
    bpy.ops.render.render(write_still=True)
    print("IDLE_RENDER", f)
arm_ob.animation_data.action = None
scene.frame_set(1)

# ---------- GLB: her iki döngü NLA track olarak ----------
bpy.ops.object.select_all(action="DESELECT")
mesh_ob.select_set(True)
arm_ob.select_set(True)
bpy.ops.export_scene.gltf(
    filepath=OUT + "/MouseRigged_anim.glb",
    use_selection=True,
    export_animations=True,
    export_animation_mode="NLA_TRACKS",
    export_def_bones=True,
    export_all_influences=False,
    export_yup=True,
)
print("ANIM_DONE")
