import { NextResponse } from "next/server";
import { query } from "@/lib/db";
import { route } from "@/lib/errors";

export const GET = route(async () => {
  try {
    await query("SELECT 1 AS ok");
    return NextResponse.json({ mysql: "up" });
  } catch {
    return NextResponse.json({ mysql: "down" }, { status: 503 });
  }
});
