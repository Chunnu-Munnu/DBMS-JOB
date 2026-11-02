import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";
import { pool, query } from "@/lib/db";
import { ApiError, route } from "@/lib/errors";
import { invalidateSchedule } from "@/lib/redis";

export const GET = route(async () => {
  await requireRole("ADMIN");
  const trains = await query("SELECT train_no, train_name, runs_on FROM TRAIN ORDER BY train_no");
  const empty = await query(
    `SELECT s.schedule_id, s.train_no, s.journey_date
       FROM SCHEDULE s
      WHERE s.journey_date >= CURDATE()
        AND NOT EXISTS (SELECT 1 FROM BOOKING b WHERE b.schedule_id = s.schedule_id)
      ORDER BY s.journey_date DESC, s.train_no LIMIT 6`,
  );
  return NextResponse.json({ trains, empty });
});

export const POST = route(async (req) => {
  await requireRole("ADMIN");
  const { trainNo, date } = await req.json();
  if (!trainNo || !date) throw new ApiError(400, "Train and date are required");
  // OUT parameters live in session variables, so one connection must do both calls.
  const conn = await pool().getConnection();
  try {
    await conn.query("CALL sp_create_schedule(?, ?, @new_schedule)", [trainNo, date]);
    const [rows] = await conn.query("SELECT @new_schedule AS schedule_id");
    return NextResponse.json((rows as { schedule_id: number }[])[0], { status: 201 });
  } finally {
    conn.release();
  }
});

export const DELETE = route(async (req) => {
  await requireRole("ADMIN");
  const id = Number(new URL(req.url).searchParams.get("id"));
  if (!id) throw new ApiError(400, "Schedule id is required");
  await query("CALL sp_delete_schedule(?)", [id]);
  await invalidateSchedule(id);
  return NextResponse.json({ deleted: id });
});
