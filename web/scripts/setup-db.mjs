// Rebuilds railway_db: runs database/NN_*.sql in order, then creates the
// least-privilege application user. Needs an admin login in .env.local.
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import mysql from "mysql2/promise";

const dir = path.resolve(import.meta.dirname, "../../database");
const env = process.env;

const conn = await mysql.createConnection({
  host: env.DB_HOST ?? "127.0.0.1",
  port: Number(env.DB_PORT ?? 3306),
  user: env.DB_ADMIN_USER ?? "root",
  password: env.DB_ADMIN_PASSWORD ?? "",
  multipleStatements: true,
});

// The mysql client handles DELIMITER itself; a driver does not, so split here.
function splitOnDelimiter(sql) {
  const batches = [];
  let delimiter = ";";
  let buffer = [];
  const flush = () => {
    const text = buffer.join("\n").trim();
    if (text) batches.push(text);
    buffer = [];
  };
  for (const line of sql.split(/\r?\n/)) {
    const m = line.match(/^\s*DELIMITER\s+(\S+)\s*$/i);
    if (m) {
      flush();
      delimiter = m[1];
    } else if (delimiter !== ";" && line.trimEnd().endsWith(delimiter)) {
      buffer.push(line.trimEnd().slice(0, -delimiter.length));
      flush();
    } else {
      buffer.push(line);
    }
  }
  flush();
  return batches;
}

const files = readdirSync(dir).filter((f) => /^\d\d_.*\.sql$/.test(f)).sort();
for (const file of files) {
  process.stdout.write(`${file} ... `);
  for (const batch of splitOnDelimiter(readFileSync(path.join(dir, file), "utf8"))) {
    await conn.query(batch);
  }
  console.log("ok");
}

// The web app connects as this user: it can read, and it can change data only
// through stored procedures, never by writing AVAILABILITY or BOOKING directly.
const appUser = env.DB_USER ?? "rail_app";
const appPass = env.DB_PASSWORD;
if (!appPass) throw new Error("DB_PASSWORD is not set");
await conn.query(`CREATE USER IF NOT EXISTS ?@'%' IDENTIFIED BY ?`, [appUser, appPass]);
await conn.query(`ALTER USER ?@'%' IDENTIFIED BY ?`, [appUser, appPass]);
await conn.query(`GRANT SELECT, EXECUTE ON railway_db.* TO ?@'%'`, [appUser]);
await conn.query(`GRANT INSERT ON railway_db.USER_ACCOUNT TO ?@'%'`, [appUser]);
await conn.query(`FLUSH PRIVILEGES`);
console.log(`application user ${appUser} ready`);

const [[counts]] = await conn.query(
  `SELECT (SELECT COUNT(*) FROM railway_db.SCHEDULE) AS schedules,
          (SELECT COUNT(*) FROM railway_db.BOOKING)  AS bookings,
          (SELECT COUNT(*) FROM railway_db.SEAT)     AS seats`,
);
console.log(counts);
await conn.end();
