@tool
extends EditorScript

# === MobileTerrain3D: Otomatik Texture Import Düzeltici (v2) ===
#
# AMAÇ:
# Diffuse/color texture'ların yanlışlıkla "Normal Map" olarak import
# edilmesini hem RETROAKTIF düzeltir hem GELECEK İÇİN ENGELLE.
#
# Normal Map = Enabled olursa Godot ETC2_RG11 (2-kanal) sıkıştırma
# uygular ve mavi kanal kaybolur. Sonuç: inspector preview'da
# psikedelik turuncu/yeşil renkler, terrain paint slot'unda yanlış
# görünüm.
#
# KULLANIM:
#   1. Bu dosyayı projenin herhangi bir yerine kaydet
#      (örn. res://fix_texture_imports.gd)
#   2. Godot'ta script editor'de aç
#   3. Üst menüden: File → Run (veya Ctrl+Shift+X)
#   4. Output panel'inde sonuçları gör
#
# İKİ AŞAMA YAPAR:
#
#   AŞAMA 1 — RETROAKTIF DÜZELTME
#   res:// altındaki .import dosyalarını tarar. Dosya adı
#   diffuse/color marker'ı içeriyorsa ("_diff", "_albedo", "_color",
#   "_ao", "_rough", "_metal", "_emit", "_height", "_specular" vs.)
#   ve compress/normal_map=1 ise → 2 (Disabled) yapar.
#
#   AŞAMA 2 — PROAKTİF ÖNLEME (yeni texture'lar için)
#   project.godot'a şu satırı yazar:
#     [importer_defaults]
#     texture={ "compress/normal_map": 2 }
#   Bu, Godot'un native "Set as Default for Texture2D" UI butonunun
#   yaptığı şeyle BİREBİR aynı.
#   Bundan sonra ProjektE eklenen her yeni texture otomatik olarak
#   Normal Map = Disabled ile import edilecek.
#
# YANİ:
#   - Bir kez çalıştır → mevcut bozuklar düzelir + gelecek için kalıcı önlem
#   - Yeni texture eklediğinde tekrar çalıştırmaya gerek yok
#
# GERİ ALMA:
# Eğer proje default'ları senin için yanlış ise:
#   Project → Project Settings → "importer_defaults" arama →
#   compress/normal_map girişini sil veya değiştir.
# Bir normal map'i script yanlışlıkla bozarsa:
#   o dosyayı FileSystem'de seç → Inspector → Import → Normal Map →
#   Enabled, Reimport.
#
# NE DOKUNMAZ:
#   - Dosya adında "_norm", "_normal", "_nrm" olan dosyalara
#   - normal_map=2 (zaten Disabled) olan dosyalara
#   - Marker'sız belirsiz isimli dosyalara (false positive riski)
#   - .godot/ internal directory'sine

const NON_NORMAL_MARKERS := [
	"_diff",
	"_diffuse",
	"_albedo",
	"_basecolor",
	"_base_color",
	"_color",
	"_col",
	"_ao",
	"_occlusion",
	"_ambient_occlusion",
	"_rough",
	"_roughness",
	"_metal",
	"_metallic",
	"_metalness",
	"_emit",
	"_emission",
	"_emissive",
	"_height",
	"_disp",
	"_displacement",
	"_specular",
	"_spec",
	"_arm",  # AO+Rough+Metal combined
	"_orm",  # Occlusion+Rough+Metal combined
]

const NORMAL_MAP_MARKERS := [
	"_norm",
	"_normal",
	"_nrm",
	"_normalmap",
	"_normal_map",
	"_nor_gl",
	"_nor_dx",
	"_nor",  # V21: AmbientCG / cc0textures convention
	"_n_ogl",
	"_n_dx",
]


func _run() -> void:
	print("")
	print("==================================================")
	print("    Texture Import Otomatik Düzeltici")
	print("==================================================")
	print("")

	var stats := {
		"scanned": 0,
		"fixed": [],  # [{source: ..., reason: ...}, ...]
		"already_normal": [],  # filename'da normal marker var, dokunulmadı
		"ambiguous": [],  # marker yok, karar verilmedi
		"already_correct": 0,  # normal_map zaten 2 (disabled)
		"errors": [],
		"defaults_action": "",  # set / already_set / error
		"defaults_detail": "",
	}

	print("--- AŞAMA 1/2: Mevcut .import dosyalarını tara ---")
	_scan_dir("res://", stats)

	print("")
	print("--- AŞAMA 2/2: Proje varsayılan import preset'ini güncelle ---")
	_setup_project_defaults(stats)

	print("")
	print("==================================================")
	print("    Sonuçlar")
	print("==================================================")

	# === ÖZET ===
	print("Taranan .import dosyası: %d" % stats["scanned"])
	print("Düzeltilen: %d" % stats["fixed"].size())
	print("Atlanan (normal map ismi var, dokunulmadı): %d" % stats["already_normal"].size())
	print("Atlanan (zaten doğru ayarda): %d" % stats["already_correct"])
	print("Atlanan (belirsiz isim, manuel kontrol gerekli): %d" % stats["ambiguous"].size())
	if stats["errors"].size() > 0:
		print("HATALAR: %d" % stats["errors"].size())
	print("")

	# === PROJE DEFAULT'LARI ===
	print("Proje varsayılan import ayarı:")
	match stats["defaults_action"]:
		"set":
			print("  ✓ AYARLANDI — bundan sonra eklenen tüm texture'lar otomatik olarak")
			print("    Normal Map = Disabled olarak import edilecek.")
			print("    %s" % stats["defaults_detail"])
		"already_set":
			print("  ✓ Zaten doğru — yeni texture'lar otomatik düzgün import oluyor.")
		"error":
			print("  ✗ Ayarlanamadı: %s" % stats["defaults_detail"])
			print("    Manuel yöntemi kullan (aşağıda).")
		_:
			print("  ? Belirsiz durum: %s" % stats["defaults_detail"])
	print("")

	# === DETAY: DÜZELTİLEN ===
	if stats["fixed"].size() > 0:
		print("--- Düzeltilen dosyalar ---")
		for entry in stats["fixed"]:
			print("  ✓ %s" % entry["source"])
			print("      Sebep: %s" % entry["reason"])
		print("")

		print("--- Reimport tetikleniyor ---")
		var efs := EditorInterface.get_resource_filesystem()
		efs.scan_sources()
		print("FileSystem scan başladı. Godot 5-10 saniye içinde texture'ları")
		print("otomatik yeniden import edecek.")
		print("")
		print("Eğer inspector preview hâlâ bozuk görünüyorsa:")
		print("  1. FileSystem dock'ta texture'a sağ tıkla → Reimport")
		print("  2. Veya: menüden Project → Reload Current Project")
	else:
		print("Düzeltilecek mevcut dosya bulunamadı.")
		print("")
		if stats["ambiguous"].size() > 0:
			print("Belirsiz isimli %d texture var (aşağıda)." % stats["ambiguous"].size())

	# === DETAY: BELİRSİZ ===
	if stats["ambiguous"].size() > 0 and stats["ambiguous"].size() <= 30:
		print("")
		print("--- Belirsiz isimli texture'lar (script dokunmadı) ---")
		print("İsimlerinde diffuse/normal marker olmayan texture'lar. Bozuksa")
		print("Inspector → Import → Normal Map → Disabled → Reimport ile manuel düzelt.")
		for source in stats["ambiguous"]:
			print("  ? %s" % source)

	# === HATALAR ===
	if stats["errors"].size() > 0:
		print("")
		print("--- HATALAR ---")
		for err in stats["errors"]:
			print("  ! %s" % err)

	# === MANUEL YÖNTEM HATIRLATMASI ===
	print("")
	print("--- MANUEL YEDEK YÖNTEM (Aşama 2 başarısızsa) ---")
	print("Eğer proje default'ları ayarlanamadıysa, manuel olarak şunu yap:")
	print("  1. FileSystem'de herhangi bir doğru texture'a tıkla")
	print("  2. Inspector → Import sekmesi")
	print("  3. Compress → Normal Map → Disabled")
	print("  4. (Opsiyonel) Compress → Mode → VRAM Compressed (mobile için)")
	print("  5. ÜST KISIMDA Preset... dropdown → 'Save Settings as Default for ...'")
	print("  6. Reimport bas")
	print("Bundan sonra yeni eklenen tüm texture'lar bu ayarla import edilecek.")

	print("")
	print("==================================================")
	print("    Tamamlandı")
	print("==================================================")
	print("")


# AŞAMA 2: Proje düzeyinde texture default'ını ayarla.
# ProjectSettings altında "importer_defaults/texture" anahtarı, Godot'un
# "Set as Default for [Texture2D]" UI butonunun yazdığı yer ile aynı.
# Yeni eklenen tüm texture'lar bu varsayılanları kullanır.
func _setup_project_defaults(stats: Dictionary) -> void:
	const KEY := "importer_defaults/texture"
	var current_raw: Variant = null
	if ProjectSettings.has_setting(KEY):
		current_raw = ProjectSettings.get_setting(KEY)

	var current: Dictionary = {}
	if typeof(current_raw) == TYPE_DICTIONARY:
		current = current_raw

	# Mevcut değeri oku
	var existing_nm: Variant = current.get("compress/normal_map", null)

	if existing_nm == 2:
		stats["defaults_action"] = "already_set"
		stats["defaults_detail"] = "importer_defaults/texture.compress/normal_map zaten 2"
		print("Proje default'ı zaten doğru (compress/normal_map=2)")
		return

	# Set/update et
	current["compress/normal_map"] = 2
	ProjectSettings.set_setting(KEY, current)

	var err := ProjectSettings.save()
	if err == OK:
		stats["defaults_action"] = "set"
		var prev_str := (
			"(önceden yoktu)" if existing_nm == null else "(önceden: %s)" % str(existing_nm)
		)
		stats["defaults_detail"] = "compress/normal_map=2 yazıldı %s" % prev_str
		print("Proje default'ı ayarlandı: importer_defaults/texture.compress/normal_map = 2")
		print("project.godot dosyası güncellendi.")
	else:
		stats["defaults_action"] = "error"
		stats["defaults_detail"] = "ProjectSettings.save() error code: %d" % err
		print("HATA: ProjectSettings.save() başarısız (kod: %d)" % err)


func _scan_dir(dir_path: String, stats: Dictionary) -> void:
	# Godot'un internal directory'lerini atla
	if dir_path.contains("/.godot/") or dir_path.ends_with("/.godot"):
		return
	# Addon'ları da atla (genelde kasıtlı import ayarları olur)
	# Yorum satırı bırakıyorum, isteyen aktif eder:
	# if dir_path.contains("/addons/"): return

	var dir := DirAccess.open(dir_path)
	if dir == null:
		stats["errors"].append("Açılamadı: " + dir_path)
		return

	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full_path := dir_path.path_join(entry)
		if dir.current_is_dir():
			_scan_dir(full_path, stats)
		elif entry.ends_with(".import"):
			_process_import_file(full_path, stats)
		entry = dir.get_next()
	dir.list_dir_end()


func _process_import_file(import_path: String, stats: Dictionary) -> void:
	stats["scanned"] += 1

	var f := FileAccess.open(import_path, FileAccess.READ)
	if f == null:
		stats["errors"].append("Okunamadı: " + import_path)
		return
	var content := f.get_as_text()
	f.close()

	# Sadece texture import'ları işle
	if not content.contains('importer="texture"'):
		return

	# Source dosya adını bul
	var source_path := _extract_string_value(content, "source_file=")
	if source_path == "":
		return

	var source_filename_lower := source_path.get_file().to_lower()

	var has_non_normal_marker := false
	var matched_marker := ""
	for marker in NON_NORMAL_MARKERS:
		if source_filename_lower.contains(marker):
			has_non_normal_marker = true
			matched_marker = marker
			break

	var has_normal_marker := false
	for marker in NORMAL_MAP_MARKERS:
		if source_filename_lower.contains(marker):
			has_normal_marker = true
			break

	# Normal map ismi varsa hiç dokunma
	if has_normal_marker:
		stats["already_normal"].append(source_path)
		return

	# Mevcut normal_map ayarını oku
	var current_nm_str := _extract_value(content, "compress/normal_map=")
	var current_nm := -1
	if current_nm_str != "":
		current_nm = current_nm_str.to_int()

	# Zaten 2 ise (disabled) — atlama, doğru
	if current_nm == 2:
		stats["already_correct"] += 1
		return

	# Marker yok ve normal_map=1 değil — belirsiz, dokunma
	if not has_non_normal_marker:
		if current_nm != 1:  # auto-detect veya zaten ok
			stats["ambiguous"].append(source_path)
			return
		# normal_map=1 ama marker yok: agresif değiliz, dokunma
		stats["ambiguous"].append(source_path + " (normal_map=1 ama marker yok)")
		return

	# BURADA: non-normal marker var (diffuse vs).
	# normal_map 0 (detect) veya 1 (enabled) ise → 2 (disabled) yap
	if current_nm == 0 or current_nm == 1:
		var new_content := _set_normal_map_value(content, 2)
		if new_content == content:
			# Param yoktu, ekle
			new_content = _insert_normal_map_value(content, 2)

		if new_content == content:
			stats["errors"].append("Düzeltme yazılamadı (%s): %s" % [matched_marker, import_path])
			return

		var wf := FileAccess.open(import_path, FileAccess.WRITE)
		if wf == null:
			stats["errors"].append("Yazma izni yok: " + import_path)
			return
		wf.store_string(new_content)
		wf.close()

		var reason := (
			"dosya adında '%s' var (diffuse/non-normal göstergesi), normal_map=%d → 2"
			% [matched_marker, current_nm]
		)
		stats["fixed"].append({"source": source_path, "reason": reason})


# .import dosyasından `key=value` formatından value'yu çıkarır
# Anahtar satır başında olmalı (boşlukla başlamasın)
func _extract_value(content: String, key: String) -> String:
	var lines := content.split("\n")
	for line in lines:
		var s := line as String
		# Strip leading/trailing whitespace ama key tam başlangıçta olmalı
		if s.begins_with(key):
			return s.substr(key.length()).strip_edges()
	return ""


# String value (tırnaklı) için
func _extract_string_value(content: String, key: String) -> String:
	var raw := _extract_value(content, key)
	if raw.length() >= 2 and raw.begins_with('"') and raw.ends_with('"'):
		return raw.substr(1, raw.length() - 2)
	return raw


# `compress/normal_map=` satırının değerini değiştirir
func _set_normal_map_value(content: String, new_value: int) -> String:
	var lines := content.split("\n")
	var out := PackedStringArray()
	var changed := false
	for line in lines:
		if (line as String).begins_with("compress/normal_map="):
			out.append("compress/normal_map=%d" % new_value)
			changed = true
		else:
			out.append(line)
	if not changed:
		return content
	return "\n".join(out)


# Eğer compress/normal_map satırı yoksa [params] bölümünün altına ekle
func _insert_normal_map_value(content: String, new_value: int) -> String:
	# [params] bölümünü bul
	var params_idx := content.find("[params]")
	if params_idx == -1:
		return content  # ekleyemeyiz, dokunma
	# [params] satırının sonunu bul
	var line_end := content.find("\n", params_idx)
	if line_end == -1:
		return content
	# Hemen sonrasına ekle
	return (
		content.substr(0, line_end + 1)
		+ ("compress/normal_map=%d\n" % new_value)
		+ content.substr(line_end + 1)
	)
