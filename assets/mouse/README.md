# MouseRigged — rig'li ev faresi

Kaynak: `31b84266-housemouse3dmodel.glb` (Tripo AI üretimi, 55.580 vertex,
4K BaseColor, **2.401 kopuk parça** — kürk kabuğu geometrisi).
Rig: Blender 5.1.2 ile headless, tamamen scriptli (scriptler `/home/user/mouse_rig`
oturum çalışma dizininde geliştirildi; üretim adımları aşağıda).

## Dosyalar
- `MouseRigged_final.blend` — ASIL teslim: tam rig (IK/FK, widget'lar, kısıtlar)
- `MouseRigged_final.glb` — oyun motoru için: skin + bake'li `idle_test` animasyonu
  (glTF kısıt/widget taşımaz; IK ile çalışmak için .blend kullanılır)
- Render'lar: iskelet doğrulama, animasyon kareleri, texture yakın planı

## Rig içeriği
- **Deform zinciri (26 kemik):** spine.01-03 → neck → head → snout, ear.L/R,
  4 bacak (upper_arm/forearm/hand, thigh/shin/foot), tail.01-06, root
- **IK:** 4 bacakta 2-kemik IK + sayısal kalibre pole hedefleri
  (forearm.L 75°, forearm.R 90°, shin.L −165°, shin.R −30°)
- **IK/FK anahtarı:** `IK_hand.L/R` ve `IK_foot.L/R` kontrol kemiklerinde
  `ik_fk` özelliği (1=IK, 0=FK). FK modunda uzuv halkalarıyla döndürülür.
- **Widget'lar (yuvarlaklar):** root yer halkası, omurga/boyun/baş/kuyruk dik
  halkalar, ayaklarda yatay IK halkaları, pole'larda küre — hepsi `WGT`
  koleksiyonunda (render'da gizli).

## Skinning notu
Mesh 2.401 kopuk kürk parçası olduğundan Blender bone-heat TÜM vertexlerde
başarısız oldu; ağırlıklar mesafe-tabanlı özel çözücüyle hesaplandı
(kemik-segment mesafesi, ters-kuvvet düşüş, vertex başına 3 kemik, 0 ağırlıksız).

## Doğrulananlar
- Kaynak GLB'de animasyon YOKTU (kontrol edildi; `idle_test` bu rig'le üretildi)
- Texture: 4K BaseColor sağlam — rest + 8 poz + animasyon karelerinde kayma yok
- IK: çökme pozunda 4 ayak yerde sabit; adım/uzanma pozları doğal
