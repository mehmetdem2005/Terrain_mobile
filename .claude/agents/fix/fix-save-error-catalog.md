    ---
    name: fix-save-error-catalog
    description: Fix: TerrainDiagnostics.error(E_SAVE_PACK_FAILED) gibi MT-001..MT-099 kodlar yerleşti...
    tools: Read, Edit, Write, Bash, Grep, Glob
    model: sonnet
    ---

    Sen **fix-save-error-catalog**. Manager'ından emir alırsın; kendi başına başlama.

## Hedef
save_orchestrator.gd + persistence_system.gd

## Görev
TerrainDiagnostics.error(E_SAVE_PACK_FAILED) gibi MT-001..MT-099 kodlar yerleştir.

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
