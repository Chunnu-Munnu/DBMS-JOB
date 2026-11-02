// End-to-end test cases against a running app and a freshly seeded database.
//   npm run db:setup && npm run build && npm start     (in one terminal)
//   npm test                                           (in another)
import mysql from "mysql2/promise";

const BASE = process.env.TEST_URL ?? "http://localhost:3000";
const env = process.env;
const admin = await mysql.createConnection({
  host: env.DB_HOST, port: Number(env.DB_PORT ?? 3306),
  user: env.DB_ADMIN_USER ?? "root", password: env.DB_ADMIN_PASSWORD ?? "", database: env.DB_NAME,
});

let passed = 0;
let failed = 0;
function check(name, ok, detail = "") {
  if (ok) passed++; else failed++;
  console.log(`${ok ? "PASS" : "FAIL"}  ${name}${!ok && detail ? `  -> ${detail}` : ""}`);
}

async function call(path, { cookie, body, method } = {}) {
  const res = await fetch(BASE + path, {
    method: method ?? (body ? "POST" : "GET"),
    headers: { "Content-Type": "application/json", ...(cookie ? { cookie } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const data = await res.json().catch(() => null);
  return { status: res.status, data, cookie: res.headers.get("set-cookie")?.split(";")[0] };
}
const login = async (email) =>
  (await call("/api/auth/login", { body: { email, password: "Demo@1234" } })).cookie;

async function expectDbError(name, sql, params, pattern) {
  try {
    await admin.query(sql, params);
    check(name, false, "was accepted");
  } catch (err) {
    check(name, pattern.test(err.sqlMessage ?? err.message), err.sqlMessage ?? err.message);
  }
}

const dateIn = (days) => new Date(Date.now() + days * 864e5).toISOString().slice(0, 10);
const JOURNEY = dateIn(20);
const pax = (name) => ({ name, age: 30, gender: "F" });

console.log("\n--- Database constraints ---");
await expectDbError("duplicate primary key", "INSERT INTO STATION VALUES ('SBC','X','Y','Z','SR')", [], /Duplicate entry/);
await expectDbError("train source equals destination",
  "INSERT INTO TRAIN VALUES ('99999','T','EXPRESS','SBC','SBC','YYYYYYY',100)", [], /chk_train_ends/);
await expectDbError("foreign key to unknown station",
  "INSERT INTO TRAIN VALUES ('99999','T','EXPRESS','SBC','ZZZZZ','YYYYYYY',100)", [], /foreign key constraint/i);
await expectDbError("malformed runs_on",
  "INSERT INTO TRAIN VALUES ('99999','T','EXPRESS','SBC','NDLS','YYYZZZZ',100)", [], /chk_runs_on/);
await expectDbError("bad phone number",
  "INSERT INTO USER_ACCOUNT (full_name,email,phone,password_hash) VALUES ('A','a@b.co','12345','h')", [], /chk_user_phone/);
await expectDbError("email without @",
  "INSERT INTO USER_ACCOUNT (full_name,email,phone,password_hash) VALUES ('A','nope','9876543210','h')", [], /chk_user_email/);
await expectDbError("availability above capacity",
  "UPDATE AVAILABILITY SET seats_available = total_seats + 1 LIMIT 1", [], /chk_avl/);
await expectDbError("availability below zero",
  "UPDATE AVAILABILITY SET seats_available = -1 LIMIT 1", [], /chk_avl/);
await expectDbError("confirmed passenger without a seat",
  "UPDATE TICKET_PASSENGER SET seat_id = NULL WHERE current_status = 'CNF' LIMIT 1", [], /chk_tp_status/);

console.log("\n--- Triggers ---");
const [[taken]] = await admin.query(
  `SELECT tp.seat_id, b.schedule_id FROM TICKET_PASSENGER tp JOIN BOOKING b ON b.pnr = tp.pnr
    WHERE tp.current_status = 'CNF' LIMIT 1`);
const [[other]] = await admin.query(
  `SELECT tp.passenger_id FROM TICKET_PASSENGER tp JOIN BOOKING b ON b.pnr = tp.pnr
    WHERE b.schedule_id = ? AND tp.seat_id <> ? AND tp.current_status = 'CNF' LIMIT 1`,
  [taken.schedule_id, taken.seat_id]);
await expectDbError("same seat twice on one schedule",
  "UPDATE TICKET_PASSENGER SET seat_id = ? WHERE passenger_id = ?", [taken.seat_id, other.passenger_id], /already allotted/);
const [[sched]] = await admin.query(
  "SELECT schedule_id FROM SCHEDULE WHERE train_no = '12627' AND journey_date = ?", [JOURNEY]);
await expectDbError("station order reversed on a direct insert",
  `INSERT INTO BOOKING (pnr,user_id,schedule_id,from_station,to_station,class_code,quota_code,distance_km,total_fare)
   VALUES ('1234567890',1,?,'NDLS','SBC','3A','GN',100,100)`, [sched.schedule_id], /Invalid station sequence/);

console.log("\n--- Search and roles ---");
const forward = await call(`/api/trains/search?from=SBC&to=NDLS&date=${JOURNEY}`);
check("SBC to NDLS finds 12627", forward.data?.some((t) => t.train_no === "12627"));
check("SBC to NDLS excludes the reverse train 12628", !forward.data?.some((t) => t.train_no === "12628"));
const middle = await call(`/api/trains/search?from=SC&to=NGP&date=${dateIn(21)}`);
const seg = middle.data?.find((t) => t.train_no === "12627");
check("segment distance is 570 km, boarding a day after origin", seg?.km === 570, JSON.stringify(seg?.km));

const priya = await login("priya@rail.test");
const rahul = await login("rahul@rail.test");
const clerk = await login("clerk@rail.test");
const tte = await login("tte@rail.test");
check("wrong password rejected",
  (await call("/api/auth/login", { body: { email: "priya@rail.test", password: "bad" } })).status === 401);
const bookBody = {
  scheduleId: sched.schedule_id, from: "SBC", to: "NDLS", classCode: "3A", quotaCode: "GN",
};
check("booking without login is 401", (await call("/api/bookings", { body: { ...bookBody, passengers: [pax("A")] } })).status === 401);
check("TTE role cannot book (403)", (await call("/api/bookings", { cookie: tte, body: { ...bookBody, passengers: [pax("A")] } })).status === 403);
const counter = await call("/api/bookings", {
  cookie: clerk,
  body: { scheduleId: sched.schedule_id, from: "YPR", to: "SC", classCode: "SL", quotaCode: "GN", customerEmail: "rahul@rail.test", passengers: [pax("Counter Pax")] },
});
const [[counterRow]] = await admin.query("SELECT booked_by_staff FROM BOOKING WHERE pnr = ?", [counter.data?.pnr]);
check("clerk counter booking records the staff id", counterRow?.booked_by_staff === 2);

console.log("\n--- Input validation through the API ---");
const longer = await call("/api/bookings", { cookie: priya, body: { ...bookBody, passengers: Array(7).fill(pax("X")) } });
check("seven passengers rejected", longer.status === 422);
const dup = await call("/api/bookings", { cookie: priya, body: { ...bookBody, classCode: "2A", passengers: [pax("Same"), pax("Same")] } });
check("duplicate passenger name is 409 and rolled back", dup.status === 409);
const [[leftover]] = await admin.query(
  "SELECT seats_available FROM AVAILABILITY WHERE schedule_id = ? AND class_code = '2A' AND quota_code = 'GN'", [sched.schedule_id]);
check("failed booking left availability untouched", leftover.seats_available === 3, String(leftover.seats_available));
const age = await call("/api/bookings", { cookie: priya, body: { ...bookBody, classCode: "2A", passengers: [{ name: "Old", age: 150, gender: "M" }] } });
check("impossible age rejected", age.status === 400 || age.status === 422, String(age.status));
const wrongWay = await call("/api/bookings", { cookie: priya, body: { ...bookBody, classCode: "2A", from: "NDLS", to: "SBC", passengers: [pax("W")] } });
check("wrong direction rejected", wrongWay.status === 422);

console.log("\n--- Concurrency: 30 simultaneous bookings for 5 seats and 2 RAC ---");
const results = await Promise.all(Array.from({ length: 30 }, (_, i) =>
  call("/api/bookings", { cookie: i % 2 ? priya : rahul, body: { ...bookBody, passengers: [pax(`Rush ${i}`)] } })));
check("all 30 requests succeeded", results.every((r) => r.status === 201), JSON.stringify(results.map((r) => r.status)));
const [counts] = await admin.query(
  `SELECT tp.current_status s, COUNT(*) n, COUNT(DISTINCT tp.seat_id) seats
     FROM TICKET_PASSENGER tp JOIN BOOKING b ON b.pnr = tp.pnr
    WHERE b.schedule_id = ? AND b.class_code = '3A' AND b.quota_code = 'GN' GROUP BY 1`, [sched.schedule_id]);
const by = Object.fromEntries(counts.map((c) => [c.s, c]));
check("exactly 5 confirmed", by.CNF?.n === 5, JSON.stringify(counts));
check("5 distinct seats, no double allotment", by.CNF?.seats === 5);
check("exactly 2 RAC", by.RAC?.n === 2);
check("the other 23 are waitlisted", by.WL?.n === 23);

console.log("\n--- Cancellation and promotion ---");
const rows = (await Promise.all(results.map((r) => call(`/api/pnr/${r.data.pnr}`)))).map((r) => r.data);
const statusOf = (s) => rows.filter((r) => r.passengers[0].current_status === s);
const victim = statusOf("CNF")[0];
const firstRac = statusOf("RAC").sort((a, b) => a.passengers[0].booking_position - b.passengers[0].booking_position)[0];
const firstWl = statusOf("WL").sort((a, b) => a.passengers[0].booking_position - b.passengers[0].booking_position)[0];
const owner = results.findIndex((r) => r.data.pnr === victim.pnr) % 2 ? priya : rahul;
const stranger = owner === priya ? rahul : priya;
check("another passenger cannot cancel this ticket",
  (await call(`/api/bookings/${victim.pnr}/cancel`, { cookie: stranger, body: {} })).status === 403);
const cancelled = await call(`/api/bookings/${victim.pnr}/cancel`, { cookie: owner, body: { reason: "test" } });
check("cancel succeeded", cancelled.status === 200, JSON.stringify(cancelled.data));
check("refund is 90% more than 48 hours out", Math.abs(cancelled.data.refund_amount - victim.total_fare * 0.9) < 0.02);
const after = async (pnr) => (await call(`/api/pnr/${pnr}`)).data.passengers[0];
const rac1 = await after(firstRac.pnr);
const wl1 = await after(firstWl.pnr);
check("earliest RAC became confirmed with a seat", rac1.current_status === "CNF" && rac1.seat_no > 0, JSON.stringify(rac1));
check("earliest WL became RAC", wl1.current_status === "RAC", JSON.stringify(wl1));
check("promotions were reported back", cancelled.data.promoted.length === 2);
const [[avail]] = await admin.query(
  "SELECT seats_available, rac_available, waitlist_count FROM AVAILABILITY WHERE schedule_id = ? AND class_code = '3A' AND quota_code = 'GN'",
  [sched.schedule_id]);
check("availability still consistent", avail.seats_available === 0 && avail.rac_available === 0 && avail.waitlist_count === 22, JSON.stringify(avail));
const again = await call(`/api/bookings/${victim.pnr}/cancel`, { cookie: owner, body: {} });
check("second cancel of the same ticket rejected", again.status === 422);
const [[hist]] = await admin.query("SELECT COUNT(*) n FROM TICKET_STATUS_HISTORY WHERE pnr = ?", [firstRac.pnr]);
check("trigger wrote the status history", hist.n === 2);

console.log("\n--- Redis ---");
const health = await call("/api/health");
check("health reports MySQL up", health.data?.mysql === "up");
if (health.data?.redis === "up") {
  const url = `/api/trains/search?from=YPR&to=NGP&date=${dateIn(22)}`;
  const first = await fetch(BASE + url);
  const second = await fetch(BASE + url);
  check("repeat search is served from cache", first.headers.get("x-cache") === "MISS" && second.headers.get("x-cache") === "HIT",
    `${first.headers.get("x-cache")}, ${second.headers.get("x-cache")}`);
  const trip = (await second.json())[0];
  await call("/api/bookings", {
    cookie: priya,
    body: { scheduleId: trip.schedule_id, from: "YPR", to: "NGP", classCode: "SL", quotaCode: "GN", passengers: [pax("Cache Buster")] },
  });
  const third = await fetch(BASE + url);
  const fresh = await third.json();
  const sl = (r) => r[0].classes.find((c) => c.class_code === "SL" && c.quota_code === "GN").seats_available;
  check("booking invalidates the cached search", third.headers.get("x-cache") === "MISS" && sl(fresh) === sl([trip]) - 1);
  const live = (await call(`/api/pnr/${firstWl.pnr}`)).data.passengers[0];
  check("live RAC rank from the sorted set: behind the older RAC", live.live_rank === 2 && live.current_position === 2, JSON.stringify(live.live_rank));
  for (let i = 0; i < 5; i++) await call("/api/auth/login", { body: { email: "sneha@rail.test", password: "bad" } });
  check("sixth login attempt is throttled",
    (await call("/api/auth/login", { body: { email: "sneha@rail.test", password: "Demo@1234" } })).status === 429);
} else {
  console.log("SKIP  Redis is down, so cache tests were skipped");
}

console.log("\n--- Admin ---");
const adminCookie = await login("admin@rail.test");
check("passenger cannot open the reports (403)", (await call("/api/admin/reports", { cookie: priya })).status === 403);
const reports = await call("/api/admin/reports", { cookie: adminCookie });
check("reports return occupancy and revenue", reports.data?.occupancy?.length > 0 && reports.data?.revenue?.length > 0);
const [[netSql]] = await admin.query(
  "SELECT SUM(CASE pay_status WHEN 'SUCCESS' THEN amount WHEN 'REFUNDED' THEN -amount ELSE 0 END) n FROM PAYMENT");
check("net revenue matches the payment ledger", Math.abs(reports.data.totals.net_revenue - netSql.n) < 0.01);
const fare = await call("/api/admin/fares", {
  cookie: adminCookie,
  body: { classCode: "SL", quotaCode: "GN", trainType: "EXPRESS", baseFare: 99, ratePerKm: 0.6, reservationChg: 20, from: dateIn(40) },
});
check("new fare rule accepted", fare.status === 201);
const [fareRows] = await admin.query(
  "SELECT effective_to FROM FARE_RULE WHERE class_code='SL' AND quota_code='GN' AND train_type='EXPRESS' ORDER BY effective_from");
check("old rule was closed, not overwritten", fareRows.length === 2 && fareRows[0].effective_to !== null && fareRows[1].effective_to === null);
const blocked = await call(`/api/admin/schedules?id=${sched.schedule_id}`, { cookie: adminCookie, method: "DELETE" });
check("run with bookings cannot be deleted", blocked.status === 400, String(blocked.status));
const list = await call("/api/admin/schedules", { cookie: adminCookie });
const emptyRun = list.data.empty[0].schedule_id;
check("empty run can be deleted", (await call(`/api/admin/schedules?id=${emptyRun}`, { cookie: adminCookie, method: "DELETE" })).status === 200);
const [[gone]] = await admin.query("SELECT COUNT(*) n FROM AVAILABILITY WHERE schedule_id = ?", [emptyRun]);
check("ON DELETE CASCADE removed its availability", gone.n === 0);
const chart = await call(`/api/tte/chart?train=12627&date=${JOURNEY}`, { cookie: tte });
check("TTE sees the chart", chart.data?.passengers?.length > 20);
check("passenger cannot see the chart", (await call(`/api/tte/chart?train=12627&date=${JOURNEY}`, { cookie: priya })).status === 403);
const ft = await call("/api/stations?q=beng");
check("full-text search finds Bengaluru stations", ft.data?.length === 2, JSON.stringify(ft.data));

console.log("\n--- Least privilege: the app's own database account ---");
const app = await mysql.createConnection({
  host: env.DB_HOST, port: Number(env.DB_PORT ?? 3306), user: env.DB_USER, password: env.DB_PASSWORD, database: env.DB_NAME,
});
for (const sql of ["UPDATE AVAILABILITY SET seats_available = 0", "DELETE FROM BOOKING", "DROP TABLE PAYMENT"]) {
  try {
    await app.query(sql);
    check(`app user blocked: ${sql}`, false, "was allowed");
  } catch (err) {
    check(`app user blocked: ${sql}`, /denied/i.test(err.message), err.message);
  }
}
await app.end();
await admin.end();

console.log(`\n${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
