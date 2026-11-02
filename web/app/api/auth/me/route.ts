import { NextResponse } from "next/server";
import { getSession } from "@/lib/auth";
import { route } from "@/lib/errors";

export const GET = route(async () => NextResponse.json(await getSession()));
