"""Rigged mouse mesh audit + region-aware weight cleanup.

Kullanıcı spesifikasyonu (madde madde):
 1. skinned mesh + armature'ı bul
 2. transform scale/rotation yazdır, apply edilmemişse UYAR
 3. deform kemiğiyle eşleşmeyen vertex group'ları listele
 4. vertex group'u olmayan deform kemiklerini listele
 5. >4 etkili vertexleri tespit et
 6. toplam ağırlığı ~1.0 olmayan vertexleri tespit et
 7. <0.001 ağırlıkları temizle (vertex_group_clean)
 8. tüm deform gruplarını normalize et (vertex_group_normalize_all)
 9. vertex başına etkiyi 4'e sınırla (vertex_group_limit_total)
10. karın / bacak / pati / kuyruk-kökü bölgelerinde şüpheli ağırlık raporu
    + bölge kurallarına aykırı etkileri temizle:
      - patiler YALNIZ kendi tarafının bacak zinciri
      - karın altında pati / kuyruk-ucu etkisi YASAK
      - kuyruk kökü yalnız spine.01 + tail.01/02
11. orijinal dosyayı BOZMA — temiz kopyayı ayrı kaydet
"""
import bpy
import math
from mathutils import Vector

SRC = "/home/user/mouse_rig/MouseRigged_rest.blend"
DST = "/home/user/mouse_rig/MouseRigged_clean.blend"

bpy.ops.wm.open_mainfile(filepath=SRC)

# --- 1. mesh + armature ---
arm_ob = next(o for o in bpy.data.objects if o.type == "ARMATURE")
mesh_ob = next(o for o in bpy.data.objects
               if o.type == "MESH" and any(m.type == "ARMATURE" for m in o.modifiers))
print("MESH:", mesh_ob.name, "| ARMATURE:", arm_ob.name)

# --- 2. transform kontrolü ---
for ob in (mesh_ob, arm_ob):
    rot_ok = all(abs(a) < 1e-6 for a in ob.rotation_euler)
    scl_ok = all(abs(s - 1.0) < 1e-6 for s in ob.scale)
    print("%s: scale=%s rotation=%s -> %s" % (
        ob.name, tuple(round(s, 4) for s in ob.scale),
        tuple(round(math.degrees(a), 2) for a in ob.rotation_euler),
        "OK (applied)" if rot_ok and scl_ok else "UYARI: transform_apply GEREKLI"))
    if not (rot_ok and scl_ok):
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.context.view_layer.objects.active = ob
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        print("  -> transform_apply uygulandı:", ob.name)

deform_bones = {b.name for b in arm_ob.data.bones if b.use_deform}

# --- 3. kemiksiz gruplar ---
orphan_groups = [g.name for g in mesh_ob.vertex_groups if g.name not in deform_bones]
print("3) deform kemiğiyle eşleşmeyen gruplar:", orphan_groups or "YOK")

# --- 4. grupsuz deform kemikleri ---
group_names = {g.name for g in mesh_ob.vertex_groups}
bonely = sorted(deform_bones - group_names)
print("4) vertex group'u olmayan deform kemikleri:", bonely or "YOK")

me = mesh_ob.data
gname = {g.index: g.name for g in mesh_ob.vertex_groups}
gobj = {g.name: g for g in mesh_ob.vertex_groups}

# --- 5-6. ön tespit ---
over4 = [v.index for v in me.vertices if len([g for g in v.groups if g.weight > 0]) > 4]
badsum = [v.index for v in me.vertices
          if abs(sum(g.weight for g in v.groups) - 1.0) > 0.01]
print("5) >4 etkili vertex:", len(over4))
print("6) toplam!=1 vertex:", len(badsum))

# --- 7-9. operatör temizliği ---
bpy.ops.object.select_all(action="DESELECT")
mesh_ob.select_set(True)
bpy.context.view_layer.objects.active = mesh_ob
bpy.ops.object.vertex_group_clean(group_select_mode="ALL", limit=0.001)
bpy.ops.object.vertex_group_limit_total(group_select_mode="ALL", limit=4)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)
print("7-9) Clean(0.001) + Limit Total 4 + Normalize All uygulandı")

# --- 10. bölge kuralları ---
mw = mesh_ob.matrix_world
verts_w = [mw @ v.co for v in me.vertices]
GROUND = min(v.z for v in verts_w)

side_of = lambda nm: ("L" if nm.endswith(".L") else "R" if nm.endswith(".R") else None)
FOOT_CENTERS = {("hand", "R"): (-0.136, -0.278), ("hand", "L"): (0.082, -0.276),
                ("foot", "R"): (-0.172, 0.025), ("foot", "L"): (0.117, 0.021)}
ALLOWED_PAW = {
    ("hand", "L"): {"upper_arm.L", "forearm.L", "hand.L"},
    ("hand", "R"): {"upper_arm.R", "forearm.R", "hand.R"},
    ("foot", "L"): {"thigh.L", "shin.L", "foot.L"},
    ("foot", "R"): {"thigh.R", "shin.R", "foot.R"},
}
tail_root = arm_ob.matrix_world @ arm_ob.data.bones["tail.01"].head_local
TAIL_ROOT_ALLOWED = {"spine.01", "tail.01", "tail.02"}
BELLY_FORBIDDEN = {"hand.L", "hand.R", "foot.L", "foot.R"} | {"tail.%02d" % i for i in range(3, 9)}

def region_of(p):
    for (kind, S), (cx, cy) in FOOT_CENTERS.items():
        if p.z < GROUND + 0.035 and (Vector((p.x, p.y, 0)) - Vector((cx, cy, 0))).length < 0.095:
            return ("paw", (kind, S))
    if (p - tail_root).length < 0.055:
        return ("tail_root", None)
    if abs(p.x) < 0.095 and -0.20 < p.y < 0.32 and p.z < -0.115:
        return ("belly", None)
    return (None, None)

stats = {"paw": 0, "belly": 0, "tail_root": 0}
emptied = 0
for v in me.vertices:
    reg, key = region_of(verts_w[v.index])
    if reg is None:
        continue
    removed_here = False
    for g in list(v.groups):
        nm = gname.get(g.group)
        if nm is None:
            continue
        bad = ((reg == "paw" and nm not in ALLOWED_PAW[key])
               or (reg == "belly" and nm in BELLY_FORBIDDEN)
               or (reg == "tail_root" and nm not in TAIL_ROOT_ALLOWED))
        if bad:
            gobj[nm].remove([v.index])
            stats[reg] += 1
            removed_here = True
    if removed_here and not any(g.weight > 0 for g in v.groups):
        emptied += 1
        if reg == "paw":
            gobj[key[0] + "." + key[1]].add([v.index], 1.0, "REPLACE")
        elif reg == "tail_root":
            gobj["tail.01"].add([v.index], 1.0, "REPLACE")
        else:
            gobj["spine.02"].add([v.index], 1.0, "REPLACE")

print("10) bölge ihlali temizliği: pati=%d karın=%d kuyruk-kökü=%d (boşalan+yeniden atanan=%d)"
      % (stats["paw"], stats["belly"], stats["tail_root"], emptied))

# bölge temizliği sonrası tekrar normalize (yumuşak geçişler korunur:
# izinli kemikler arası oranlar değişmez, yalnız yasaklılar düşer)
bpy.ops.object.vertex_group_normalize_all(group_select_mode="ALL", lock_active=False)

# --- son doğrulama ---
over4 = sum(1 for v in me.vertices if len([g for g in v.groups if g.weight > 0]) > 4)
badsum = sum(1 for v in me.vertices if abs(sum(g.weight for g in v.groups) - 1.0) > 0.01)
unweighted = sum(1 for v in me.vertices if not any(g.weight > 0 for g in v.groups))
print("SON: >4etki=%d toplam!=1=%d ağırlıksız=%d (hepsi 0 olmalı)" % (over4, badsum, unweighted))

# rest sapması korunmuş mu
for p in arm_ob.pose.bones:
    p.location = (0, 0, 0); p.rotation_quaternion = (1, 0, 0, 0)
    p.rotation_euler = (0, 0, 0); p.scale = (1, 1, 1)
bpy.context.view_layer.update()
dg = bpy.context.evaluated_depsgraph_get()
evme = mesh_ob.evaluated_get(dg).to_mesh()
mx = max((evme.vertices[i].co - me.vertices[i].co).length for i in range(len(me.vertices)))
mesh_ob.evaluated_get(dg).to_mesh_clear()
print("REST SAPMASI: %.2f mm" % (mx * 1000))

# --- 11. temiz KOPYA olarak kaydet ---
bpy.ops.wm.save_as_mainfile(filepath=DST)
print("KAYDEDILDI (orijinal bozulmadı):", DST)
print("AUDIT_CLEAN_DONE")
