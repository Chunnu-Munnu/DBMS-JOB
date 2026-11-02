import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";
import { callProc, query } from "@/lib/db";
import { ApiError, route } from "@/lib/errors";
import { invalidateSchedule, syncQueue, withBookingLock } from "@/lib/redis";

type Ctx = { params: Promise<{ pnr: string }> };
type Booking = { user_id: number; schedule_id: number; class_code: string; quota_code: string };

export const POST = route<Ctx>(async (req, { params }) => {
  const session = await requireRole("PASSENGER", "CLERK", "ADMIN");
  const { pnr } = await params;
  const { passengerId, reason } = await req.json();

  const [booking] = await query<Booking>(
    "SELECT user_id, schedule_id, class_code, quota_code FROM BOOKING WHERE pnr = ?",
    [pnr],
  );
  if (!booking) throw new ApiError(404, "PNR not found");
  if (session.role === "PASSENGER" && booking.user_id !== session.id) {
    throw new ApiError(403, "This ticket belongs to another account");
  }

  const sets = await withBookingLock(booking.schedule_id, booking.class_code, () =>
    callProc("sp_cancel_ticket", [pnr, passengerId ?? null, reason ?? null]),
  );

  await invalidateSchedule(booking.schedule_id);
  await syncQueue(booking.schedule_id, booking.class_code, booking.quota_code);

  return NextResponse.json({ ...sets[0][0], promoted: sets[1] ?? [] });
});
