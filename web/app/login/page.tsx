"use client";

import Link from "next/link";
import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { api } from "@/lib/api";

const HOME: Record<string, string> = { ADMIN: "/admin", CLERK: "/", TTE: "/tte", PASSENGER: "/" };

export default function LoginPage() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const router = useRouter();

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError("");
    try {
      const user = await api<{ role: string }>("/api/auth/login", { email, password });
      router.push(HOME[user.role] ?? "/");
    } catch (err) {
      setError((err as Error).message);
    }
  }

  return (
    <>
      <h1>Log in</h1>
      <form className="card" onSubmit={submit} style={{ maxWidth: 400 }}>
        <label>Email<input type="email" value={email} onChange={(e) => setEmail(e.target.value)} required /></label>
        <label style={{ marginTop: 10 }}>Password
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} required />
        </label>
        {error && <p className="error">{error}</p>}
        <p><button>Log in</button></p>
        <p className="muted">New here? <Link href="/register">Create an account</Link></p>
      </form>
    </>
  );
}
