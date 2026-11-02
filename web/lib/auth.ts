import { SignJWT, jwtVerify } from "jose";
import { cookies } from "next/headers";
import { ApiError } from "./errors";

export type Role = "PASSENGER" | "CLERK" | "TTE" | "ADMIN";
export type Session = { id: number; name: string; email: string; role: Role };

const COOKIE = "rail_session";

function secret() {
  const value = process.env.JWT_SECRET;
  if (!value) throw new Error("JWT_SECRET is not set");
  return new TextEncoder().encode(value);
}

export async function startSession(user: Session) {
  const token = await new SignJWT(user)
    .setProtectedHeader({ alg: "HS256" })
    .setIssuedAt()
    .setExpirationTime("8h")
    .sign(secret());
  (await cookies()).set(COOKIE, token, {
    httpOnly: true, // page scripts cannot read it, which limits XSS damage
    sameSite: "lax",
    secure: process.env.NODE_ENV === "production",
    path: "/",
    maxAge: 8 * 3600,
  });
}

export async function endSession() {
  (await cookies()).delete(COOKIE);
}

export async function getSession(): Promise<Session | null> {
  const token = (await cookies()).get(COOKIE)?.value;
  if (!token) return null;
  try {
    const { payload } = await jwtVerify(token, secret());
    return payload as unknown as Session;
  } catch {
    return null;
  }
}

// Server-side role check. Hiding a button in the UI is not access control; this is.
export async function requireRole(...roles: Role[]): Promise<Session> {
  const session = await getSession();
  if (!session) throw new ApiError(401, "Please log in");
  if (roles.length && !roles.includes(session.role)) {
    throw new ApiError(403, "Your role is not allowed to do this");
  }
  return session;
}
