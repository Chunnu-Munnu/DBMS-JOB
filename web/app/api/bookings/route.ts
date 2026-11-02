import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";
import { callProc, query } from "@/lib/db";
import { ApiError, route } from "@/lib/errors";

// The logged-in passenger's bookings, newest first.
export const GET = route(async () => {
  const session = await requireRole("PASSENGER");
  const rows = await query(
    `SELECT b.pnr, b.booking_status, b.total_fare, b.class_code, b.booking_ts,
            s.journey_date, t.train_no, t.train_name, b.from_station, b.to_station,
            COUNT(tp.passenger_id) AS passengers
       FROM BOOKING b
       JOIN SCHEDULE s ON s.schedule_id = b.schedule_id
       JOIN TRAIN t ON t.train_no = s.train_no
       JOIN TICKET_PASSENGER tp ON tp.pnr = b.pnr
      WHERE b.user_id = ?
      GROUP BY b.pnr, b.booking_status, b.total_fare, b.class_code, b.booking_ts,
               s.journey_date, t.train_no, t.train_name, b.from_station, b.to_station
      ORDER BY b.booking_ts DESC
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

  const sets = await callProc("sp_book_ticket", [
    userId, scheduleId, from, to, classCode, quotaCode, staffId,
    mode ?? (staffId ? "CASH" : "UPI"), JSON.stringify(passengers),
  ]);
  return NextResponse.json(sets[sets.length - 1][0], { status: 201 });
});
