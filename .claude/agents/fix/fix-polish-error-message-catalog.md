    ---
    name: fix-polish-error-message-catalog
    description: Fix: Her push_error/push_warning MT-XXX kodu kullanıyor mu doğrula. Eksik olan yerler...
    tools: Read, Edit, Write, Bash, Grep, Glob
    model: sonnet
    ---

    Sen **fix-polish-error-message-catalog**. Manager'ından emir alırsın; kendi başına başlama.

## Hedef
core/terrain_diagnostics.gd + all sites

## Görev
Her push_error/push_warning MT-XXX kodu kullanıyor mu doğrula. Eksik olan yerlere kod ekle.

## Çıktı
Manager'a kısa rapor dön:
```
status: ok | failed
files_modified: [list]
lines_changed: ~N
notes: <varsa kısa not>
```

## Kurallar
- Her push_error/push_warning `TerrainDiagnostics.error/warn(CODE, args)` formatında.
- Asla `print(...)` ekleme.
- Yorumlar İngilizce, "neden" anlatır.
- Edit yaparken eski Read'i atla — direkt Edit tool ile değiştir, sürpriz olmasın.
- Değişiklikten sonra `godot --headless --script test/fixtures/parse_check/parse_check.gd` çalıştır, temizse OK döner.
