import { NextResponse } from "next/server";
import { query } from "@/lib/db";
import { route } from "@/lib/errors";

export const GET = route(async () => {
  const rows = await query(
    "SELECT station_code, station_name, city FROM STATION ORDER BY station_name",
  );
  return NextResponse.json(rows);
});
