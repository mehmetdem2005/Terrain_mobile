# MouseRigged Pro — rig'li ev faresi (v2, profesyonel ağırlık pipeline'ı)

Kaynak: `31b84266-housemouse3dmodel.glb` (Tripo AI, 55.580 vertex, 4K BaseColor,
**2.401 kopuk kürk parçası**). Rig: Blender 5.1.2 headless, tamamen scriptli.

## v2'de değişen (kullanıcı geri bildirimi: "kuyruk kayık, göğüs altı texture kayıyor")
1. **Ağırlıklar — profesyonel pipeline:** elle mesafe-tabanlı ağırlıklar atıldı.
   Yerine endüstri tekniği: mesh kopyası → **voxel remesh** (0.012) ile tek
   su-geçirmez proxy (11.108 vertex) → proxy'de **bone-heat** (0 başarısız) →
   **Data Transfer** (POLYINTERP_NEAREST) ile 55.580 kürk vertexine aktarım →
   limit 4 + normalize → **Corrective Smooth** modifier.
2. **Kuyruk yeniden:** merkez hattı, ark-merkezi etrafında deterministik
   θ-parametrizasyonuyla çıkarıldı (greedy izin zikzakı bitti); 8 kemik,
   taban (0.003, 0.411) → uç (0.256, 0.463), z sapması < 1 cm; tüm kemiklerde
   `align_roll(Z-up)` → süpürme/kıvrılma eksenleri tutarlı.
3. IK pole açıları yeni roll'lara göre yeniden sayısal kalibre edildi
   (forearm.L 45°, forearm.R 90°, shin.L 120°, shin.R 90°).

## Dosyalar
- `MouseRigged_rest.blend` — ASIL: tam rig (IK/FK anahtarlı, yuvarlak widget'lar)
- `MouseRigged_rest.glb` — oyun motoru: skin + bake'li `idle_test` animasyonu
- Render'lar: kuyruk süpürme/kıvrılma, göğüs altı yakın plan, animasyon karesi

## Rig içeriği
28 deform kemiği (omurga 3, boyun, baş, burun, kulak ×2, bacak 4×3, kuyruk 8) +
root. 4 bacakta 2-kemik IK + pole; `IK_hand/foot.L/R` üzerinde `ik_fk` (1=IK,
0=FK). Widget'lar `WGT` koleksiyonunda (render'da gizli).

## Doğrulama kanıtları
- Kuyruk süpürme + yukarı kıvrılma: pürüzsüz spiral, texture takipte (render'lar)
- Göğüs altı nefes + pati-kalkık yakın planlar: doku kayması yok
- Çökmede 4 ayak IK ile yerde; kaynak GLB'de animasyon yoktu, `idle_test` eklendi

## v3 (pati/yön düzeltmesi)
- Pati kemikleri mesh PCA ekseninde: ön patiler 51° dışa açık, arka 9-15°
  (düz-öne bakan eski kemikler glTF viewer kontrolünde yakalandı)
- Anatomik L/R takası: fare -Y yönüne bakar, anatomik sol = +X; 22 kemik
  yeniden adlandı, vertex group/constraint otomatik eşlendi (0 kayıp)
- IK pole yeniden kalibre (75/45/75/120°)

## v4 (arka bacak düzeltmesi)
- Arka zincir ölçülen kütle akışına oturtuldu: kalça haunch tepesinde
  (y≈0.23), diz görünür bacak sütununun önünde (y≈0.12), topuk ölçülen
  noktada — uyluk artık görünür bacağın içinde
- Pati uçları parmak-yelpaze merkeziyle (PCA eksen ucu değil) hesaplandı
- Ağırlıklar sıfırdan yeniden çözüldü (proxy bone-heat + transfer, 0 ağırlıksız)
- IK pole yeniden kalibre (75/45/90/105°)

## v5 (kürk-şeridi + taşma matematiksel doğrulama)
- Yırtık yelpaze kök nedeni: tüy-şeridi vertexlerinin FARKLI kemiklere
  bağlanması (en-yakın-yüzey aktarımının yan etkisi). Çözüm: 2.140 küçük
  şeride kök-vertex ağırlığı tek blok verildi (kürk-kartı standardı);
  261 büyük yüzey parçası per-vertex kaldı.
- Kemik-içeride testi artık ışın-parite (3 eksen çoğunluk): kalça kökü
  53 mm dışarıdaydı, içeri çekildi; tüm eklemler hacim içinde doğrulandı.
- Corrective Smooth kaldırıldı: GLB modifier taşımaz, viewer ile blend
  artık AYNI deformasyonu gösterir (önceki fark bundandı).
- IK pole yeniden kalibre; idle pati hareketi yumuşatıldı.

## v6 — REST KESINLIGI (kritik düzeltme)
- KÖK NEDEN bulundu: rig REST halinde mesh'i 259.8 mm'ye kadar deforme
  ediyordu! (a) COPY_ROTATION kısıtı patiyi -Y yönlü kontrol kemiğinin
  rotasyonuna zorluyordu (patilerin "ters/yamuk" görünmesinin ve yırtılmanın
  ana sebebi), (b) IK pole kaba kalibrasyonu rest'te 17-28 mm hata
  bırakıyordu. GLB'ye bu bozuk poz "bind" olarak gidiyordu.
- Düzeltme: IK kontrol kemikleri deform kemiğiyle aynı yönelime alındı
  (COPY_ROTATION rest'te kimlik), pole hedefleri gerçek bükülme düzleminden
  hesaplandı, pole açıları 0.5° hassasiyetle tarandı (rest hatası 0.01-0.12mm).
- SONUÇ: rest sapması max 0.4 mm (evaluated-vertex ölçümü) — model kendi
  şeklinde, hiçbir uzuv oynatılmadı. GLB animasyonsuz ihraç edildi.
