@tool
class_name TerrainDiagnostics
extends RefCounted

# Central catalog for MobileTerrain3D push_error / push_warning sites.
# Every diagnostic carries an MT-XXX (error) or MT-WXX (warning) code so
# users can grep their Output panel and jump straight to the explanation.
#
# Usage:
#   TerrainDiagnostics.error(TerrainDiagnostics.E_SAVE_PACK_FAILED, [path, err])
#   TerrainDiagnostics.warn(TerrainDiagnostics.W_PAINT_SLOT_OOB, [slot])

# ---- Errors (MT-001..MT-099) ----
const E_SAVE_PACK_FAILED := "MT-001: PackedScene.pack failed for '%s' (err=%d)"
const E_SAVE_RESOURCE_FAILED := "MT-002: ResourceSaver.save failed for '%s' (err=%d)"
const E_EXTERNAL_MISSING := "MT-003: external_data_path set but .res missing: '%s'"
const E_HEIGHT_DATA_MISMATCH := "MT-004: height_data.size (%d) != map_size² (%d)"
const E_PAINT_SLOT_OOB := "MT-005: paint slot %d out of range [0..3]; ignoring"
const E_CHUNK_OOB := "MT-006: chunk coord %s out of grid"
const E_SHADER_LOAD := "MT-007: failed to load terrain shader at '%s'"
const E_SPLATMAP_SIZE_DRIFT := "MT-008: splatmap image %dx%d != map_size %d; skipping paint dab"

# ---- Warnings (MT-WXX) ----
const W_AUTO_EXTERNALIZE := "MT-W01: Auto-externalising %d cells → '%s'"
const W_BRUSH_MASK_FALLBACK := "MT-W02: brush_mask load failed, using shape fallback"
const W_TEXTURE_SLOT_CAP := "MT-W03: En fazla %d doku slot'u olabilir (splatmap RGBA). Önce bir slot'u boşalt."
const W_DETECT_NEED_ALBEDO := "MT-W04: Slot %d: önce Albedo texture'ını seç, sonra Tespit'e bas."
const W_DETECT_NO_PATH := "MT-W05: Slot %d: Albedo texture'ın disk yolu yok; otomatik tespit atlandı."
const W_DETECT_NO_SIBLINGS := "MT-W06: Slot %d: '%s' için kardeş map bulunamadı. Marker '_diff'/'_albedo'/... olmalı."
const W_LARGE_HEIGHTMAP := "MT-W07: Büyük heightmap (%d cells, ~%.1f MB). Inspector'da 'Click To Externalize' ile .res dosyasına kaydet."
const W_RESTORE_INVALID := "MT-W10: Restore target no longer valid; skipping."
const W_INLINE_NO_PATH := "MT-W11: external_data_path boş, inline edilecek bir şey yok."
const W_INLINE_RES_MISSING := "MT-W12: External .res '%s' bulunamadı. Yol korundu — dosyayı geri koyup tekrar dene."
const W_INLINE_LOAD_FAILED := "MT-W13: External load height_data'yı dolduramadı; inline iptal edildi."
const W_TEXTURE_SLOTS_UNDERFLOW := "MT-W14: terrain_textures (%d) < %d kanal; eksik slotlar boş (gri) görünür."
const W_DETECT_STORED_UNUSED := "MT-W15: Slot %d: %s map(ler)i bulunup sahneye kaydedildi, ama bu mobil shader onları render ETMİYOR (yalnızca albedo/normal/roughness/AO). Özel shader için saklanır."


static func error(code_template: String, args: Array = []) -> void:
	if args.is_empty():
		push_error(code_template)
	else:
		push_error(code_template % args)


static func warn(code_template: String, args: Array = []) -> void:
	if args.is_empty():
		push_warning(code_template)
	else:
		push_warning(code_template % args)
