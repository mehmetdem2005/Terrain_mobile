    ---
    name: fix-extract-chunk-system
    description: Fix: node.gd: initialize_terrain, _create_chunk, update_chunk_mesh, _mark_chunk_dirty...
    tools: Read, Edit, Write, Bash, Grep, Glob
    model: sonnet
    ---

    Sen **fix-extract-chunk-system**. Manager'ından emir alırsın; kendi başına başlama.

## Hedef
systems/chunk_system.gd YENİ

## Görev
node.gd: initialize_terrain, _create_chunk, update_chunk_mesh, _mark_chunk_dirty, force_update_all, garbage_collect_multimeshes, repurpose_multimesh_to, _get_or_create_multimesh, restore_multimeshes → ChunkSystem (Node3D olmak zorunda değil, RefCounted). Node bir instance composeluyor.

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
