/**
 * AutoNPC v4.0 — kalıcı state. (D1 düzeltmesi)
 * v3'te state RAM'deydi; dünya kapanınca envanter/görev/skill kayboluyordu.
 * v4: WorkerState, entity dynamic property'sinde versiyonlu JSON olarak yaşar.
 */
import { STATE_PROP } from "./config.js";
import { createDefaultState, cacheState, cachedState } from "./state.js";

/** Çalışma-zamanına ait, persiste edilmeyen alanlar. */
const RUNTIME_KEYS = new Set(["dirty"]);

export function loadState(worker) {
  const cached = cachedState(worker.id);
  if (cached) return cached;
  let st;
  try {
    const raw = worker.getDynamicProperty(STATE_PROP);
    if (typeof raw === "string" && raw.length) {
      const data = JSON.parse(raw);
      if (data && data.schema === 4) {
        st = { ...createDefaultState(worker), ...data, dirty: false };
        // Çökme anında yarım kalan koşu-zamanı alanları güvenli sıfırla:
        st.trace = Array.isArray(st.trace) ? st.trace : [];
      }
    }
  } catch (e) { /* bozuk veri: temiz başla */ }
  if (!st) st = createDefaultState(worker);
  cacheState(worker.id, st);
  return st;
}

export function saveState(worker, st) {
  if (!st.dirty) return false;
  try {
    const out = {};
    for (const [k, v] of Object.entries(st)) if (!RUNTIME_KEYS.has(k)) out[k] = v;
    worker.setDynamicProperty(STATE_PROP, JSON.stringify(out));
    st.dirty = false;
    return true;
  } catch (e) {
    return false; // property limiti vb.; bir sonraki tick tekrar dener
  }
}
