import { NextResponse } from "next/server";
import { query } from "@/lib/db";
import { route } from "@/lib/errors";

export const GET = route(async (req) => {
  const typed = new URL(req.url).searchParams.get("q")?.replace(/[^\p{L}\p{N} ]/gu, " ").trim();
  if (typed && typed.length >= 3) {
    // Full-text search; each typed word must prefix-match. Ranked by relevance.
    const terms = typed.split(/\s+/).map((word) => `+${word}*`).join(" ");
    const rows = await query(
      `SELECT station_code, station_name, city
         FROM STATION
        WHERE MATCH(station_name, city) AGAINST (? IN BOOLEAN MODE)
        ORDER BY MATCH(station_name, city) AGAINST (? IN BOOLEAN MODE) DESC, station_name`,
      [terms, terms],
    );
    return NextResponse.json(rows);
  }
  const rows = await query(
    "SELECT station_code, station_name, city FROM STATION ORDER BY station_name",
  );
  return NextResponse.json(rows);
});
