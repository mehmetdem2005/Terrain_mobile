/** AutoNPC v4.0 — merkezi ayarlar. Tüm sayısal ayar SADECE burada. */
export const VERSION = "v4.0";
export const NS = "autonpc";
export const WORKER_ID = `${NS}:worker`;
export const GUIDE_ID = `${NS}:guide_book`;
export const GUIDE_NAME = "AutoNPC Yönetim Kitabı v4.0";
export const TAG_WORKER = `${NS}.worker`;
export const STATE_PROP = `${NS}:state`;
export const PANEL_PROP = `${NS}:panel_req`;

// --- tick bütçeleri (D6 düzeltmesi: hiçbir worker tick'i sınırsız iş yapamaz)
export const TICK_INTERVAL = 1;
export const SCAN_BLOCKS_PER_TICK = 350;   // tarayıcı blok-okuma bütçesi / worker / tick
export const ASTAR_MAX_NODES = 700;        // tek plan için düğüm sınırı
export const REPLAN_COOLDOWN = 20;         // tick; ardışık A* planları arası
export const PERSIST_EVERY = 20;           // kirli state kaç tick'te bir yazılır

// --- hareket
export const WALK_SPEED = 0.16;            // blok / tick (yol takibi)
export const ARRIVE_DIST = 0.45;           // ara nokta varış toleransı
export const STUCK_LIMIT = 30;             // ilerleme yoksa re-plan
export const MAX_FALL = 3;                 // güvenli düşüş
export const STEP_UP = 1;                  // tırmanılabilir basamak

// --- etkileşim
export const INTERACT_RANGE = 3.05;
export const INTERACT_VERTICAL = 4.5;
export const PICKUP_RADIUS = 1.35;
export const PICKUP_SEARCH_RADIUS = 4.0;
export const DROP_WAIT_TICKS = 30;

// --- tarama yarıçapları
export const SCAN_RADIUS = 14;
export const TREE_SCAN_RADIUS = 18;
export const ORE_SCAN_RADIUS = 20;

// --- görev
export const OBSTACLE_MAX_PER_TARGET = 8;
export const BLACKLIST_TICKS = 600;
export const PANEL_DEBOUNCE = 10;          // tick; D4 düzeltmesi
