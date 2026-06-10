/**
 * AutoNPC v5.2 — ASABİ KİŞİLİK + rastgele isimler.
 * Her işçi spawn'da isim alır; olaylara karakterli (hafif huysuz) Türkçe
 * tepkiler verir. Spam koruması: işçi başına 200 tick cooldown.
 */
import { world, system } from "@minecraft/server";

export const NAMES = [
  "Kazma Kemal", "Somurtkan Selim", "Homurtu Hasan", "Bıkkın Burak", "Aksi Ahmet",
  "Çatık Çetin", "Söylenen Suat", "Gergin Galip", "Ters Tahir", "Hırçın Hüsnü",
  "Dertli Davut", "Veryansın Veli", "Küskün Kenan", "Sert Sefer", "Öfke Ömer",
];
const used = new Set();
export function pickName() {
  const free = NAMES.filter((n) => !used.has(n));
  const n = (free.length ? free : NAMES)[Math.floor(Math.random() * (free.length ? free.length : NAMES.length))];
  used.add(n);
  return n;
}

const LINES = {
  spawn: ["İş başı... yine mi ben?", "Kazma nerde? Hadi bitirelim şunu.", "Mesai başladı, karışmayın."],
  stuck: ["Bu ne biçim arazi böyle?!", "TIKANDIM! Kazıyorum ama sinirliyim.", "Kim koydu bu duvarı buraya?!"],
  distress: ["İMDAT! Sıkıştım, biri gelsin!", "Burada mahsur kaldım, yardım edin be!", "Çukura düştüm, gülmeyin de gelin!"],
  rescue_go: ["Tamam tamam geliyorum, bağırma!", "Tutun bir yere, yoldayım.", "Yine mi kurtarma? Pekala..."],
  rescue_done: ["Kurtardım. Borçlusun bana.", "Bir daha düşersen orada kalırsın!", "Hadi işine, ben de işime."],
  done: ["Bitti. Alkış beklemiyorum.", "Tamamdır. Sıradaki!", "Hallettim, kolaydı zaten."],
  hurt: ["AH! Kim vurdu lan?!", "Canım yandı, fena olacak şimdi!", "Bunu yapan pişman olacak!"],
  creeper: ["CREEPER! Kalkan! Geri!", "Yeşil şeytan yine burada!", "Patlarsan üstüme, fena kızarım!"],
  mine: ["Maden vakti. Karanlık ve ben.", "Demir kokusu alıyorum...", "Kazmaya devam, söylene söylene."],
};

const cooldown = new Map(); // workerId -> son konuşma tick'i

export function angry(st, kind) {
  try {
    const id = st?.npcName ?? "İşçi";
    const wid = st?._wid ?? id;
    const now = system.currentTick;
    if (now - (cooldown.get(wid) ?? -999) < 200) return;
    cooldown.set(wid, now);
    const pool = LINES[kind] ?? LINES.done;
    const line = pool[Math.floor(Math.random() * pool.length)];
    world.sendMessage(`§6<${id}>§r §7${line}§r`);
  } catch (e) { /* sohbet opsiyonel */ }
}
