import bcrypt from "bcryptjs";
import { NextResponse } from "next/server";
import { startSession, type Role } from "@/lib/auth";
import { query } from "@/lib/db";
import { ApiError, route } from "@/lib/errors";

type Account = { id: number; name: string; email: string; password_hash: string; role: Role };

export const POST = route(async (req) => {
  const { email, password } = await req.json();
  if (!email || !password) throw new ApiError(400, "Email and password are required");

  // UNION: passengers and staff live in separate tables but share one login form.
  const rows = await query<Account>(
    `SELECT user_id AS id, full_name AS name, email, password_hash, 'PASSENGER' AS role
       FROM USER_ACCOUNT WHERE email = ?
     UNION ALL
     SELECT staff_id, staff_name, email, password_hash, role
       FROM STAFF WHERE email = ?`,
    [email, email],
  );
  const account = rows[0];
  // Same message either way, so the form does not reveal which emails exist.
  if (!account || !(await bcrypt.compare(password, account.password_hash))) {
    throw new ApiError(401, "Wrong email or password");
  }
  const user = { id: account.id, name: account.name, email: account.email, role: account.role };
  await startSession(user);
  return NextResponse.json(user);
});
