import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";
import { callProc, query } from "@/lib/db";
import { ApiError, route } from "@/lib/errors";

type Ctx = { params: Promise<{ pnr: string }> };

export const POST = route<Ctx>(async (req, { params }) => {
  const session = await requireRole("PASSENGER", "CLERK", "ADMIN");
  const { pnr } = await params;
  const { passengerId, reason } = await req.json();

  const [booking] = await query<{ user_id: number }>("SELECT user_id FROM BOOKING WHERE pnr = ?", [pnr]);
  if (!booking) throw new ApiError(404, "PNR not found");
  if (session.role === "PASSENGER" && booking.user_id !== session.id) {
    throw new ApiError(403, "This ticket belongs to another account");
  }

  const sets = await callProc("sp_cancel_ticket", [pnr, passengerId ?? null, reason ?? null]);
  return NextResponse.json({ ...sets[0][0], promoted: sets[1] ?? [] });
});
