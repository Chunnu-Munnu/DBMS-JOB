import { NextResponse } from "next/server";
import { ApiError, route } from "@/lib/errors";
import { cacheSearch, countSearch, getCachedSearch } from "@/lib/redis";
import { searchTrains, type TrainResult } from "@/lib/search";

export const GET = route(async (req) => {
  const params = new URL(req.url).searchParams;
  const from = params.get("from");
  const to = params.get("to");
  const date = params.get("date");
  if (!from || !to || !date) throw new ApiError(400, "from, to and date are required");
  if (from === to) throw new ApiError(400, "Source and destination must differ");

  await countSearch(from, to);

  // Cache-aside: try Redis, fall back to MySQL, then fill Redis.
  const key = `${from}:${to}:${date}`;
  const cached = await getCachedSearch<TrainResult[]>(key);
  if (cached) return NextResponse.json(cached, { headers: { "X-Cache": "HIT" } });

  const results = await searchTrains(from, to, date);
  await cacheSearch(key, results, results.map((t) => t.schedule_id));
  return NextResponse.json(results, { headers: { "X-Cache": "MISS" } });
});
