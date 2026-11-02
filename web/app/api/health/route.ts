import { NextResponse } from "next/server";
import { query } from "@/lib/db";
import { route } from "@/lib/errors";
import { redisUp } from "@/lib/redis";

// 200 as long as MySQL answers. Without Redis the app is degraded, not down.
export const GET = route(async () => {
  const redis = (await redisUp()) ? "up" : "down";
  try {
    await query("SELECT 1 AS ok");
    return NextResponse.json({ mysql: "up", redis });
  } catch {
    return NextResponse.json({ mysql: "down", redis }, { status: 503 });
  }
});
