import { NextResponse } from "next/server";
import { requireRole } from "@/lib/auth";
import { route } from "@/lib/errors";
import { rebuildAllQueues, redisUp } from "@/lib/redis";

// After a Redis restart: reload every live queue from the WAITLIST table.
export const POST = route(async () => {
  await requireRole("ADMIN");
  if (!(await redisUp())) return NextResponse.json({ error: "Redis is not reachable" }, { status: 503 });
  return NextResponse.json({ queuesRebuilt: await rebuildAllQueues() });
});
