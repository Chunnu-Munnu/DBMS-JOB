import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";
import { query } from "@/lib/db";
import { ApiError, route } from "@/lib/errors";

export const GET = route(async () => {
  await requireRole("ADMIN");
  const rows = await query(
    `SELECT rule_id, class_code, quota_code, train_type, base_fare, rate_per_km, reservation_chg,
            effective_from, effective_to
       FROM FARE_RULE ORDER BY train_type, class_code, quota_code, effective_from DESC`,
  );
  return NextResponse.json(rows);
});

export const POST = route(async (req) => {
  await requireRole("ADMIN");
  const { classCode, quotaCode, trainType, baseFare, ratePerKm, reservationChg, from } = await req.json();
  if (!classCode || !quotaCode || !trainType || !from) throw new ApiError(400, "All fields are required");
  await query("CALL sp_set_fare(?, ?, ?, ?, ?, ?, ?)", [
    classCode, quotaCode, trainType, baseFare, ratePerKm, reservationChg ?? 0, from,
  ]);
  return NextResponse.json({ ok: true }, { status: 201 });
});
