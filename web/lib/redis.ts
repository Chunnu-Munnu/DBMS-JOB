import { randomUUID } from "node:crypto";
import Redis from "ioredis";
import { query } from "./db";

// MySQL is the source of truth. Everything in Redis can be rebuilt from it, so a
// Redis failure must slow the app down at most, never break it. Each helper here
// therefore "fails open": on any error it logs and carries on as if Redis was absent.
const store = globalThis as unknown as { railRedis?: Redis };

function client(): Redis | null {
  if (!process.env.REDIS_URL) return null;
  if (!store.railRedis) {
    store.railRedis = new Redis(process.env.REDIS_URL, {
      lazyConnect: false,
      enableOfflineQueue: false, // fail at once when disconnected, do not queue
      maxRetriesPerRequest: 1,
      connectTimeout: 1000,
      retryStrategy: (times) => Math.min(times * 500, 5000),
    });
    store.railRedis.on("error", (err) => console.warn("Redis:", err.message));
  }
  return store.railRedis;
}

async function safe<T>(work: (r: Redis) => Promise<T>, fallback: T): Promise<T> {
  const r = client();
  if (!r || r.status !== "ready") return fallback;
  try {
    return await work(r);
  } catch (err) {
    console.warn("Redis command failed:", (err as Error).message);
    return fallback;
  }
}

export async function redisUp() {
  const r = client();
  // The first request after a server start may arrive mid-connect; give it a moment.
  for (let wait = 0; r && r.status !== "ready" && wait < 10; wait++) {
    await new Promise((done) => setTimeout(done, 100));
  }
  return safe(async (ready) => (await ready.ping()) === "PONG", false);
}

// ---------- Availability cache (cache-aside) ----------
// Each cached search is listed in a set per schedule, so a booking can delete
// exactly the searches it made stale. The TTL is the safety net if a delete is missed.
const SEARCH_TTL_SECONDS = 60;

export async function getCachedSearch<T>(key: string): Promise<T | null> {
  const value = await safe((r) => r.get(`search:${key}`), null);
  return value ? (JSON.parse(value) as T) : null;
}

export async function cacheSearch(key: string, value: unknown, scheduleIds: number[]) {
  await safe(async (r) => {
    const tx = r.multi().set(`search:${key}`, JSON.stringify(value), "EX", SEARCH_TTL_SECONDS);
    for (const id of scheduleIds) {
      tx.sadd(`sched:${id}:searches`, `search:${key}`).expire(`sched:${id}:searches`, SEARCH_TTL_SECONDS * 2);
    }
    await tx.exec();
  }, undefined);
}

export async function invalidateSchedule(scheduleId: number) {
  await safe(async (r) => {
    const keys = await r.smembers(`sched:${scheduleId}:searches`);
    await r.del(`sched:${scheduleId}:searches`, ...keys);
  }, undefined);
}

// ---------- Booking lock (SET NX with expiry) ----------
// Queues rush traffic in Redis so requests are not all piling up on MySQL row locks.
// It is not what prevents overbooking: SELECT ... FOR UPDATE in sp_book_ticket does that,
// which is why the app may go ahead without the lock if Redis is down or busy.
const RELEASE_IF_OWNER = `
  if redis.call("get", KEYS[1]) == ARGV[1] then return redis.call("del", KEYS[1]) end
  return 0`;

export async function withBookingLock<T>(scheduleId: number, classCode: string, work: () => Promise<T>): Promise<T> {
  const key = `lock:${scheduleId}:${classCode}`;
  const token = randomUUID();
  const acquired = await safe(async (r) => {
    for (let attempt = 0; attempt < 40; attempt++) {
      if (await r.set(key, token, "PX", 3000, "NX")) return true;
      await new Promise((done) => setTimeout(done, 25));
    }
    return false;
  }, false);
  try {
    return await work();
  } finally {
    if (acquired) await safe((r) => r.eval(RELEASE_IF_OWNER, 1, key, token), 0);
  }
}

// ---------- Live queues (sorted sets) ----------
// Score = position, member = passenger id. ZRANK gives a passenger's live place in
// O(log n). The sets are rebuilt from MySQL after each committed change, so the
// relational WAITLIST table stays authoritative.
const queueKey = (s: number, c: string, q: string, type: string) => `queue:${s}:${c}:${q}:${type}`;

export async function syncQueue(scheduleId: number, classCode: string, quotaCode: string) {
  const rows = await query<{ passenger_id: number; position: number; queue_type: string }>(
    `SELECT passenger_id, position, queue_type FROM WAITLIST
      WHERE schedule_id = ? AND class_code = ? AND quota_code = ? AND is_active`,
    [scheduleId, classCode, quotaCode],
  );
  await safe(async (r) => {
    const tx = r.multi();
    for (const type of ["RAC", "WL"]) {
      const key = queueKey(scheduleId, classCode, quotaCode, type);
      tx.del(key);
      const members = rows.filter((m) => m.queue_type === type).flatMap((m) => [String(m.position), String(m.passenger_id)]);
      if (members.length) tx.zadd(key, ...members);
    }
    await tx.exec();
  }, undefined);
}

export async function queueSnapshot(scheduleId: number, classCode: string, quotaCode: string) {
  return safe(async (r) => ({
    rac: await r.zrange(queueKey(scheduleId, classCode, quotaCode, "RAC"), "0", "-1"),
    wl: await r.zrange(queueKey(scheduleId, classCode, quotaCode, "WL"), "0", "-1"),
  }), null);
}

export async function queueRank(scheduleId: number, classCode: string, quotaCode: string, type: string, passengerId: number) {
  const rank = await safe((r) => r.zrank(queueKey(scheduleId, classCode, quotaCode, type), String(passengerId)), null);
  return rank === null ? null : rank + 1;
}

// Rebuilds every queue, for use after a Redis restart.
export async function rebuildAllQueues(): Promise<number> {
  const groups = await query<{ schedule_id: number; class_code: string; quota_code: string }>(
    "SELECT DISTINCT schedule_id, class_code, quota_code FROM WAITLIST WHERE is_active",
  );
  for (const g of groups) await syncQueue(g.schedule_id, g.class_code, g.quota_code);
  return groups.length;
}

// ---------- Trending routes (sorted set as a counter) ----------
export async function countSearch(from: string, to: string) {
  await safe((r) => r.zincrby("trending:routes", 1, `${from}-${to}`), "");
}

export async function trendingRoutes(limit = 5) {
  const flat = await safe((r) => r.zrevrange("trending:routes", "0", String(limit - 1), "WITHSCORES"), [] as string[]);
  const out: { route: string; searches: number }[] = [];
  for (let i = 0; i < flat.length; i += 2) out.push({ route: flat[i], searches: Number(flat[i + 1]) });
  return out;
}

// ---------- Login throttle (INCR with expiry) ----------
const MAX_FAILED_LOGINS = 5;

export const loginBlocked = async (email: string) =>
  Number(await safe((r) => r.get(`login:fail:${email}`), "0")) >= MAX_FAILED_LOGINS;

export async function recordFailedLogin(email: string) {
  await safe(async (r) => {
    const failures = await r.incr(`login:fail:${email}`);
    if (failures === 1) await r.expire(`login:fail:${email}`, 900);
  }, undefined);
}

export const clearFailedLogins = (email: string) => safe((r) => r.del(`login:fail:${email}`), 0);

export async function redisStats() {
  return safe(async (r) => ({
    keys: await r.dbsize(),
    memory: (await r.info("memory")).match(/used_memory_human:(\S+)/)?.[1] ?? "?",
  }), null);
}
