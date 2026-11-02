import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";
import { callProc, query } from "@/lib/db";
import { ApiError, route } from "@/lib/errors";
import { invalidateSchedule, syncQueue, withBookingLock } from "@/lib/redis";

// The logged-in passenger's bookings and cancellations in the last year.
export const GET = route(async () => {
  const session = await requireRole("PASSENGER");
  const rows = await query(
    `SELECT h.*, COUNT(tp.passenger_id) AS passengers, b.class_code, s.train_no
       FROM v_passenger_history h
       JOIN BOOKING b ON b.pnr = h.pnr
       JOIN SCHEDULE s ON s.schedule_id = b.schedule_id
       JOIN TICKET_PASSENGER tp ON tp.pnr = h.pnr
      WHERE h.user_id = ? AND h.booking_ts >= NOW() - INTERVAL 1 YEAR
      GROUP BY h.pnr, h.user_id, h.booking_ts, h.booking_status, h.total_fare, h.journey_date,
               h.train_name, h.from_station, h.to_station, h.refunded, h.last_cancelled_at,
               b.class_code, s.train_no
      ORDER BY h.booking_ts DESC
      LIMIT 50`,
    [session.id],
  );
  return NextResponse.json(rows);
});

export const POST = route(async (req) => {
  const session = await requireRole("PASSENGER", "CLERK", "ADMIN");
  const { scheduleId, from, to, classCode, quotaCode, mode, passengers, customerEmail } = await req.json();
  if (!scheduleId || !from || !to || !classCode || !quotaCode) {
    throw new ApiError(400, "Journey details are incomplete");
  }
  if (!Array.isArray(passengers) || passengers.some((p) => !p?.name?.trim())) {
    throw new ApiError(400, "Every passenger needs a name");
  }

  // A clerk books at the counter for an existing passenger account.
  let userId = session.id;
  let staffId: number | null = null;
  if (session.role !== "PASSENGER") {
    const [customer] = await query<{ user_id: number }>(
      "SELECT user_id FROM USER_ACCOUNT WHERE email = ?",
      [customerEmail ?? ""],
    );
    if (!customer) throw new ApiError(404, "No passenger account with that email");
    userId = customer.user_id;
    staffId = session.id;
  }

  const sets = await withBookingLock(scheduleId, classCode, () =>
    callProc("sp_book_ticket", [
      userId, scheduleId, from, to, classCode, quotaCode, staffId,
      mode ?? (staffId ? "CASH" : "UPI"), JSON.stringify(passengers),
    ]),
  );

  // MySQL has committed. Only now is Redis brought in line.
  await invalidateSchedule(scheduleId);
  await syncQueue(scheduleId, classCode, quotaCode);

  return NextResponse.json(sets[sets.length - 1][0], { status: 201 });
});
