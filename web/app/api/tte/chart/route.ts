import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";
import { query } from "@/lib/db";
import { ApiError, route } from "@/lib/errors";
import { queueSnapshot } from "@/lib/redis";

// The examiner's chart: everyone on one train and date, coach by coach.
export const GET = route(async (req) => {
  await requireRole("TTE", "ADMIN");
  const params = new URL(req.url).searchParams;
  const train = params.get("train");
  const date = params.get("date");
  if (!train || !date) throw new ApiError(400, "Train and date are required");

  const passengers = await query<{ schedule_id: number; class_code: string; quota_code: string }>(
    `SELECT schedule_id, pnr, class_code, quota_code, coach_code, seat_no, berth_type, passenger_name,
            age, gender, current_status, current_position, from_station, to_station
       FROM v_pnr_status
      WHERE train_no = ? AND journey_date = ? AND current_status <> 'CAN'
      ORDER BY class_code, coach_code IS NULL, coach_code, seat_no, current_status, current_position`,
    [train, date],
  );

  let liveQueue = null;
  const queued = passengers.find((p) => (p as unknown as { current_status: string }).current_status !== "CNF");
  if (queued) liveQueue = await queueSnapshot(queued.schedule_id, queued.class_code, queued.quota_code);
  return NextResponse.json({ passengers, liveQueue });
});
