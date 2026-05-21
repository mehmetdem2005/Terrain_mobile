# Godot 4.6.2 Mobile Reference

Domain knowledge for the studio's mobile work. Load this file whenever a ticket touches mobile (Forward Mobile renderer, Godot Android Editor, Android export, Android Plugin v2).

## The three renderers — what they are and aren't

Godot 4.x ships with three rendering methods, all selectable at project level. Plugins that touch rendering must know which is active.

### Forward+ (desktop, default)
- **APIs**: Vulkan (Linux/Windows), D3D12 (Windows), Metal (macOS)
- **Use case**: High-end desktop, lots of lights, complex shading
- **Features**: clustered lighting, SDFGI, volumetric fog, full HDR, compute shaders, all post-processing
- **Tradeoffs**: heavy bandwidth on mobile-class GPUs

### Forward Mobile (mobile + lower-end desktop)
- **APIs**: Vulkan (Android), Metal (iOS), D3D12 (Windows mobile), Vulkan (some Linux)
- **Use case**: Mobile devices, tablets, lower-spec desktop
- **Features**: single-pass forward lighting, subpass-based tile rendering, MSAA
- **Critical constraints**:
  - Color buffer is R10G10B10A2 UNORM (half the bandwidth, reduced HDR precision)
  - Glow and DoF cannot use efficient subpass path → expensive when enabled
  - Compute shaders limited or unsupported
  - SDFGI unavailable
  - Volumetric fog limited
  - HDR is technically supported but with reduced max values (clipping risk for very bright pixels)

### Compatibility (legacy, Quest 3)
- **APIs**: OpenGL 3 (most platforms), OpenGL ES 3.0 (Android legacy)
- **Use case**: Very old GPUs, Meta Quest 3 standalone, fallback target
- **Features**: most basic; lots of advanced features unavailable
- **Tradeoffs**: broadest compatibility, lowest feature ceiling

## Renderer fallback (since Godot 4.4)

If a project selects Forward+ but the GPU doesn't support Vulkan/D3D12/Metal, Godot 4.4+ falls back automatically:

```
Forward+ → Forward Mobile → Compatibility (if `fallback_to_opengl3` enabled)
```

This is set in project settings. To check the current project:
```bash
grep -E "rendering_method|fallback_to_opengl3" <project>/project.godot
```

**Plugin implication**: A plugin that assumes Forward+ features (SDFGI, full HDR, compute shaders) WILL fail or degrade when the project falls back. If the plugin checks renderer at runtime:

```gdscript
var renderer := ProjectSettings.get_setting("rendering/renderer/rendering_method")
# returns "forward_plus", "mobile", or "gl_compatibility"
```

## Godot Android Editor — what it is

Godot ships an Android port of the editor itself. Developers can edit and export projects from an Android device (phone or tablet). Released starting around Godot 4.3.

### What works
- Most of the desktop editor
- 2D and 3D scene editing
- Script editor (with on-screen keyboard)
- Export to Android target from the Android editor itself
- Most EditorPlugin functionality

### What's different
- **Touch input only** — no mouse, no keyboard (except on-screen)
- **Smaller screen** — docks compress or stack; some default Godot panels reflow
- **Scoped storage** on modern Android — file picker uses Android storage APIs
- **No shell access** — `OS.execute()` is severely limited; no subprocess spawning
- **GPU is mobile-class** — Forward+ may not work; default is Forward Mobile
- **Performance is mobile-class** — what's fast on desktop may be slow here

### Plugin compatibility on Android editor

Your EditorPlugin will load on the Android editor automatically unless it has hard incompatibilities. Common issues:

| Plugin pattern | Android editor result |
|----------------|----------------------|
| Right-click context menu | Inaccessible — no right-click |
| Keyboard shortcut as primary interaction | Inaccessible — no keyboard until on-screen |
| Tooltip-only documentation | Inaccessible — no hover |
| Drag-and-drop | Works with touch but UI may need larger targets |
| Mouse-wheel scrolling | Inaccessible — use touch swipe |
| Small click targets (<24px) | Hard to hit accurately on touch |
| Hardcoded file paths | Fails on scoped storage |
| Shell commands via OS.execute | Fails |

### Verifying Android editor compatibility (best-effort, no device)

In studio context (no Android device available), the Android Editor Specialist:
1. Reads plugin source for the patterns above
2. Documents incompatibilities in plugin README under "Android editor compatibility"
3. Either: adapts the plugin to work with touch, OR explicitly declares desktop-only

## Android Plugin v2 — the OTHER thing

**Critical disambiguation**: "Android plugin for Godot" is ambiguous. Two distinct products:

### EditorPlugin
- Lives in `addons/<name>/`
- Written in GDScript
- Extends the Godot editor at design time
- Runs in the editor process
- Can target Android (editor → Android editor), but is fundamentally an editor extension
- This is what 90% of plugin requests are

### Android Plugin v2
- Lives outside addons/ — it's an AAR library
- Written in Kotlin or Java (not GDScript)
- Provides Android-native APIs to the game at *runtime*, on the Android device
- Examples: camera access, accelerometer, ads, in-app billing, push notifications, file picker
- Introduced in Godot 4.2; replaces deprecated v1 (`.gdap`)
- Packaged via `EditorExportPlugin`, not `EditorPlugin`
- Dependency on `org.godotengine:godot` Android library (MavenCentral)
- Requires Gradle build
- A `GodotPlugin` Kotlin class is the entry point

### When the user says "Android plugin"
Ask, don't assume:
- Goal: extend the editor authoring experience? → EditorPlugin
- Goal: access Android device APIs from the running game? → Android Plugin v2
- Goal: both? → two separate deliverables, one of each type

## Mobile performance budgets (enforced by Mobile Performance Specialist)

| Metric | Budget |
|--------|--------|
| Plugin enable time on mid-tier Android | <200ms |
| Plugin steady-state CPU on mid-tier Android | <5% |
| Plugin RAM overhead | <50MB |
| Thermal stability (sustained 5min) | no throttle |
| Touch target minimum size | 44x44 device pixels |
| Inspector refresh on Android editor | <33ms (one frame at 30fps) |

## Texture compression for mobile

For plugin sample assets or mobile-targeted plugins:
- **ETC2** (ETC2_RGB / ETC2_RGBA) — universal Android compatibility
- **ASTC** — modern devices (Android 8+ with ASTC LDR; required for Android 10+ on Vulkan); higher quality and smaller files than ETC2
- **S3TC/BPTC** — desktop only; don't ship for mobile-only
- **PVRTC** — old iOS; not needed for Android editor

Project setting:
```
rendering/textures/vram_compression/import_etc2_astc=true
```

## Shader compatibility quick check

Plugin shaders for mobile must avoid:
- `dFdx`, `dFdy` (screen-space derivatives — break subpass tile rendering)
- Multi-sample texture reads in fragment shader
- Compute shaders
- `discard;` (breaks tile-based rendering optimization on mobile GPUs)
- Reading from neighboring fragments

Use instead:
- Precomputed values in vertex shader → interpolated to fragment
- Single-sample textures
- Vertex-based effects when possible

## Common mobile-specific bugs in plugins

Catalog (continuously updated by Studio Knowledge Curator):

1. **Plugin enables a Forward+-only feature in sample scene** — when run on mobile, sample looks wrong. Mitigation: check renderer at runtime, disable advanced features OR provide a separate mobile sample.

2. **Plugin uses uncompressed PNG samples — 4-10MB each** — slow load, large APK. Mitigation: ship .ctex files (compressed) or reference 1K sample textures.

3. **Plugin uses `_process` to poll mouse position** — wastes mobile battery, doesn't translate to touch. Mitigation: use input events, not polling.

4. **Plugin hardcodes touch-unfriendly controls** — buttons 16px tall, can't tap. Mitigation: design for 44x44px minimum.

5. **Plugin assumes desktop file path semantics** — uses `~` or `\\` paths. Mitigation: stay in `res://` for plugin data; use `OS.get_user_data_dir()` for user data.

---

End of mobile reference. The three mobile specialists (Mobile Renderer, Android Editor, Android Plugin v2) all draw from this document.
