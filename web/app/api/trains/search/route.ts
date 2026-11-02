import { NextResponse } from "next/server";
import { ApiError, route } from "@/lib/errors";
import { searchTrains } from "@/lib/search";

export const GET = route(async (req) => {
  const params = new URL(req.url).searchParams;
  const from = params.get("from");
  const to = params.get("to");
  const date = params.get("date");
  if (!from || !to || !date) throw new ApiError(400, "from, to and date are required");
  if (from === to) throw new ApiError(400, "Source and destination must differ");
  return NextResponse.json(await searchTrains(from, to, date));
});
