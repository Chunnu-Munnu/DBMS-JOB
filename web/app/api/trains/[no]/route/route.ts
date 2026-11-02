import { NextResponse } from "next/server";
import { query } from "@/lib/db";
import { route } from "@/lib/errors";

type Ctx = { params: Promise<{ no: string }> };

export const GET = route<Ctx>(async (_req, { params }) => {
  const { no } = await params;
  const rows = await query(
    `SELECT r.seq_no, r.station_code, s.station_name, r.arrival_time, r.departure_time,
            r.day_offset, r.dist_from_src
       FROM ROUTE r JOIN STATION s ON s.station_code = r.station_code
      WHERE r.train_no = ? ORDER BY r.seq_no`,
    [no],
  );
  return NextResponse.json(rows);
});
