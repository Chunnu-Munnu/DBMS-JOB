import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { query } from "@/lib/db";
import { ApiError, route } from "@/lib/errors";

type Ctx = { params: Promise<{ pnr: string }> };
type Row = Record<string, unknown> & { user_id: number };

export const GET = route<Ctx>(async (_req, { params }) => {
  const { pnr } = await params;
  if (!/^\d{10}$/.test(pnr)) throw new ApiError(400, "A PNR is exactly 10 digits");

  const rows = await query<Row>("SELECT * FROM v_pnr_status WHERE pnr = ? ORDER BY passenger_id", [pnr]);
  if (!rows.length) throw new ApiError(404, "PNR not found");

  const history = await query(
    `SELECT h.changed_at, tp.passenger_name, h.old_status, h.new_status
       FROM TICKET_STATUS_HISTORY h
       JOIN TICKET_PASSENGER tp ON tp.passenger_id = h.passenger_id
      WHERE h.pnr = ? ORDER BY h.history_id`,
    [pnr],
  );

  const session = await getSession();
  const { user_id, ...first } = rows[0];
  const canCancel =
    !!session && (session.role === "CLERK" || session.role === "ADMIN" ||
      (session.role === "PASSENGER" && session.id === user_id));
  return NextResponse.json({ ...first, canCancel, passengers: rows, history });
});
