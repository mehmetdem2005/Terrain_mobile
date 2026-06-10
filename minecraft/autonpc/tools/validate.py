#!/usr/bin/env python3
"""AutoNPC v4.0 doğrulayıcı: JSON lint, UUID/bağımlılık, BP-RP kimlik eşleşmeleri,
script import grafiği dosya varlığı."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
fail = 0


def err(msg):
    global fail
    fail += 1
    print("HATA:", msg)


def ok(msg):
    print("OK  :", msg)


# 1) tum JSON'lar parse
jsons = {}
for p in sorted(ROOT.rglob("*.json")):
    if "node_modules" in p.parts:
        continue
    try:
        jsons[p] = json.loads(p.read_text(encoding="utf-8"))
    except Exception as e:
        err(f"JSON parse: {p.relative_to(ROOT)}: {e}")
ok(f"{len(jsons)} JSON parse edildi")

bp_manifest = jsons.get(ROOT / "BP/manifest.json")
rp_manifest = jsons.get(ROOT / "RP/manifest.json")

# 2) UUID benzersiz + BP->RP bagimliligi
uuids = []
for m in (bp_manifest, rp_manifest):
    if not m:
        err("manifest eksik")
        continue
    uuids.append(m["header"]["uuid"])
    for mod in m["modules"]:
        uuids.append(mod["uuid"])
if len(uuids) != len(set(uuids)):
    err("UUID'ler benzersiz değil")
else:
    ok(f"{len(uuids)} UUID benzersiz")
dep_uuids = [d.get("uuid") for d in bp_manifest.get("dependencies", []) if "uuid" in d]
if rp_manifest["header"]["uuid"] not in dep_uuids:
    err("BP, RP'ye uuid ile bağımlı değil")
else:
    ok("BP -> RP bağımlılığı doğru")

# 3) kimlik eşleşmeleri
def collect_strings(obj, out):
    if isinstance(obj, dict):
        for k, v in obj.items():
            collect_strings(k, out)
            collect_strings(v, out)
    elif isinstance(obj, list):
        for v in obj:
            collect_strings(v, out)
    elif isinstance(obj, str):
        out.add(obj)

bp_entity = jsons[ROOT / "BP/entities/worker.behavior.json"]
rp_entity = jsons[ROOT / "RP/entity/worker.entity.json"]["minecraft:client_entity"]["description"]
if bp_entity["minecraft:entity"]["description"]["identifier"] != rp_entity["identifier"]:
    err("BP/RP entity identifier uyuşmuyor")
else:
    ok(f"entity id: {rp_entity['identifier']}")

# RP referansları gerçekten tanımlı mı
geo_ids, anim_ids, rc_ids, ac_ids = set(), set(), set(), set()
collect_strings(jsons[ROOT / "RP/models/entity/worker.geo.json"], geo_ids)
collect_strings(jsons[ROOT / "RP/animations/worker.animation.json"], anim_ids)
collect_strings(jsons[ROOT / "RP/render_controllers/worker.render_controllers.json"], rc_ids)
collect_strings(jsons[ROOT / "RP/animation_controllers/worker.animation_controllers.json"], ac_ids)
geo_ref = rp_entity["geometry"]["default"]
if not any(geo_ref in s for s in geo_ids):
    err(f"geometry tanımsız: {geo_ref}")
else:
    ok(f"geometry: {geo_ref}")
for name, ref in rp_entity.get("animations", {}).items():
    pool = anim_ids | ac_ids
    if not any(ref in s for s in pool):
        err(f"animasyon tanımsız: {ref}")
ok("entity animasyon referansları tarandı")
for rc in rp_entity.get("render_controllers", []):
    if not any(rc in s for s in rc_ids):
        err(f"render controller tanımsız: {rc}")

# item icon <-> item_texture
icon = jsons[ROOT / "BP/items/guide_book.json"]["minecraft:item"]["components"]["minecraft:icon"]
tex = jsons[ROOT / "RP/textures/item_texture.json"]["texture_data"]
if icon not in tex:
    err(f"item icon '{icon}' item_texture.json'da yok")
else:
    tex_path = ROOT / "RP" / (tex[icon]["textures"] + ".png")
    if not tex_path.exists():
        err(f"doku dosyası yok: {tex_path.relative_to(ROOT)}")
    else:
        ok(f"item icon -> {tex[icon]['textures']}.png")

# entity texture dosyası
for t in jsons[ROOT / "RP/entity/worker.entity.json"]["minecraft:client_entity"]["description"]["textures"].values():
    if not (ROOT / "RP" / (t + ".png")).exists():
        err(f"entity dokusu yok: {t}.png")
    else:
        ok(f"entity dokusu: {t}.png")

# 4) script import grafiği: her göreli import mevcut dosyaya gitmeli
scripts = sorted((ROOT / "BP/scripts").rglob("*.js"))
imp_re = re.compile(r'import\s+[^"\']+["\']([^"\']+)["\']')
for s in scripts:
    for m in imp_re.finditer(s.read_text(encoding="utf-8")):
        spec = m.group(1)
        if spec.startswith("@"):
            if spec not in ("@minecraft/server", "@minecraft/server-ui"):
                err(f"{s.name}: bilinmeyen modül {spec}")
            continue
        target = (s.parent / spec).resolve()
        if not target.exists():
            err(f"{s.relative_to(ROOT)}: import bulunamadı -> {spec}")
ok(f"{len(scripts)} script import grafiği doğrulandı")

# 5) script animasyon adları RP'de tanımlı mı
anim_refs = set()
for s in scripts:
    for m in re.finditer(r'playAnimation\("([^"]+)"\)', s.read_text(encoding="utf-8")):
        anim_refs.add(m.group(1))
for a in sorted(anim_refs):
    if not any(a in x for x in anim_ids):
        err(f"script animasyonu RP'de yok: {a}")
    else:
        ok(f"script animasyonu: {a}")

print()
if fail:
    print(f"VALIDATE_FAILED ({fail} hata)")
    sys.exit(1)
print("VALIDATE_OK")
