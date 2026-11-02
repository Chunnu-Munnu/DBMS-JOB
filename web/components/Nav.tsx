"use client";

import Link from "next/link";
import { usePathname, useRouter } from "next/navigation";
import { useEffect, useState } from "react";

type User = { name: string; role: string } | null;

export default function Nav() {
  const [user, setUser] = useState<User>(null);
  const path = usePathname();
  const router = useRouter();

  useEffect(() => {
    fetch("/api/auth/me").then((r) => (r.ok ? r.json() : null)).then(setUser).catch(() => setUser(null));
  }, [path]);

  async function logout() {
    await fetch("/api/auth/logout", { method: "POST" });
    setUser(null);
    router.push("/");
  }

  return (
    <nav>
      <Link href="/"><strong>Railway Reservation</strong></Link>
      <Link href="/pnr">PNR status</Link>
      {user?.role === "PASSENGER" && <Link href="/my-bookings">My bookings</Link>}
      {user?.role === "ADMIN" && <Link href="/admin">Dashboard</Link>}
      {(user?.role === "TTE" || user?.role === "ADMIN") && <Link href="/tte">Examiner chart</Link>}
      <span className="grow" />
      {user ? (
        <>
          <span>{user.name} ({user.role})</span>
          <button onClick={logout}>Log out</button>
        </>
      ) : (
        <>
          <Link href="/login">Log in</Link>
          <Link href="/register">Register</Link>
        </>
      )}
    </nav>
  );
}
