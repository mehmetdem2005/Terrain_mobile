# Brush Masks (Fırça Maskeleri)

Bu klasör MobileTerrain3D fırça maskelerini içerir. **Fırça maskesi**
fırça aracından (Yükselt / Boya / Yumuşat / vb.) ayrı bir kavramdır:

- **Araç** = ne yapılacak (yükselt, alçalt, boya, yumuşat...)
- **Maske** = etki hangi şekille dağılacak (yuvarlak, ring, gürültü, splotch...)

Yani aynı "Yükselt" aracı `mountain1.png` ile **doğal dağ kabartma**
yapar, `peak.png` ile **sivri tepe** çıkarır, `ring_thin.png` ile
**krater kenarı** oluşturur.

## V21 ile gelen 20 default maske

| Grup | Dosya | Mantık |
|------|-------|--------|
| Circle | `circle_soft`, `circle_medium`, `circle_hard`, `circle_solid` | Yumuşak → sert geçiş yelpazesi |
| Ring | `ring_thin`, `ring_thick` | Krater kenarı, halka |
| Square | `square_soft`, `square_hard` | Plato, blok |
| Diamond | `diamond` | L1-norm (manhattan) düşüş |
| Hill | `hill_soft`, `hill_sharp` | Gauss tepecik |
| Peak | `peak` | Çok dar sivri uç |
| Noise | `noise_smooth`, `noise_rough` | Doğal düzensizlik (low / high freq) |
| Stones | `stones` | Noktalı, kayalık |
| Streaks | `streaks` | Yönlü, rüzgâr/erozyon |
| Splotches | `splotches` | Düzensiz büyük lekeler |
| Vegetation | `vegetation_patch` | Bitki/çim dağıtmak için yoğun nokta |
| Special | `star`, `crescent` | Yıldız, hilal |

## Kendi maskeni eklemek

1. 256×256 (veya daha büyük) gri tonlamalı PNG/EXR/JPG/WEBP üret
2. Beyaz (255) = tam etki, siyah (0) = etki yok
3. Daire dışını (köşeleri) siyah bırak — fırça yarıçapı sınırı maskenin kendi içinde
4. Bu klasöre at: `addons/mobile_terrain/brushes/`
5. Godot'da otomatik import olur
6. Plugin'in **🖌 Maske** butonuna bas → **↻ Yenile** → yeni maskeni gör → tıkla, seç

## Teknik

Runtime'da maske her brush stroke pixel'inde sample'lanır:
```glsl
uv = (px - center) / radius * 0.5 + 0.5  # → [0, 1]²
falloff = mask.r (ix=uv.x*w, iy=uv.y*h)
strength = brush_strength * falloff
```

Yani 256×256 resolution genelde fazla detay. 100×100 (Terrain3D varsayılanı)
da iyi çalışır — fark fark edilmez çünkü brush radius (8-50 unit) maskeyi
zaten çok aşağıya örnekler.

Daha büyük maskeler (1024×1024+) bellekte alan kapar, sample süresi
aynı O(1) kalır ama disk import biraz yavaşlar. Çoğu kullanım için
256×256 yeterli.

## Default'a dönmek

Maske grid'inde **"✕ Maske Yok"** butonuna basarsan, addon eski hard-coded
şekil sistemine (Yumuşak/Keskin/Kare/Elmas/Gürültü dropdown'u) düşer.
Yani V20'den önceki sahnelerde renderlamanız bozulmaz.
