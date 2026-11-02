import bcrypt from "bcryptjs";
import { NextResponse } from "next/server";
import type { ResultSetHeader } from "mysql2";
import { startSession } from "@/lib/auth";
import { pool } from "@/lib/db";
import { ApiError, route } from "@/lib/errors";

export const POST = route(async (req) => {
  const { fullName, email, phone, password } = await req.json();
  if (!fullName || !email || !phone) throw new ApiError(400, "Name, email and phone are required");
  if (typeof password !== "string" || password.length < 8) {
    throw new ApiError(400, "Password must be at least 8 characters");
  }
  // Email and phone format are enforced by chk_user_email and chk_user_phone in MySQL.
  const hash = await bcrypt.hash(password, 10);
  const [result] = await pool().execute<ResultSetHeader>(
    "INSERT INTO USER_ACCOUNT (full_name, email, phone, password_hash) VALUES (?, ?, ?, ?)",
    [fullName, email, phone, hash],
  );
  const user = { id: result.insertId, name: fullName, email, role: "PASSENGER" as const };
  await startSession(user);
  return NextResponse.json(user, { status: 201 });
});
