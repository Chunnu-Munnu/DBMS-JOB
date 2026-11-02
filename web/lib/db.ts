import mysql, { type Pool, type RowDataPacket } from "mysql2/promise";

// One pool per server process. Next.js dev reloads modules, so keep it on globalThis.
const store = globalThis as unknown as { railPool?: Pool };

export function pool(): Pool {
  if (!store.railPool) {
    store.railPool = mysql.createPool({
      host: process.env.DB_HOST,
      port: Number(process.env.DB_PORT ?? 3306),
      user: process.env.DB_USER,
      password: process.env.DB_PASSWORD,
      database: process.env.DB_NAME,
      connectionLimit: 10,
      waitForConnections: true,
      queueLimit: 50,
      connectTimeout: 5000,
      dateStrings: true,
      decimalNumbers: true,
    });
  }
  return store.railPool;
}

const RETRYABLE = new Set(["ER_LOCK_DEADLOCK", "ER_LOCK_WAIT_TIMEOUT"]);

// A deadlock victim was rolled back by InnoDB, so running it again is safe.
async function withRetry<T>(work: () => Promise<T>, attempts = 3): Promise<T> {
  for (let attempt = 1; ; attempt++) {
    try {
      return await work();
    } catch (err) {
      const code = (err as { code?: string }).code ?? "";
      if (!RETRYABLE.has(code) || attempt >= attempts) throw err;
      await new Promise((r) => setTimeout(r, 50 * attempt));
    }
  }
}

export async function query<T = RowDataPacket>(sql: string, params: unknown[] = []): Promise<T[]> {
  const [rows] = await withRetry(() => pool().execute(sql, params as never[]));
  return rows as T[];
}

// Calls a stored procedure and returns only its result sets, without the status packet.
export async function callProc(name: string, params: unknown[]): Promise<RowDataPacket[][]> {
  const marks = params.map(() => "?").join(",");
  const [result] = await withRetry(() => pool().query(`CALL ${name}(${marks})`, params));
  return (result as unknown[]).filter(Array.isArray) as RowDataPacket[][];
}
