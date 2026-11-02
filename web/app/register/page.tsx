"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";
import { api } from "@/lib/api";

export default function RegisterPage() {
  const [form, setForm] = useState({ fullName: "", email: "", phone: "", password: "" });
  const [error, setError] = useState("");
  const router = useRouter();
  const field = (key: keyof typeof form) => ({
    value: form[key],
    onChange: (e: { target: { value: string } }) => setForm({ ...form, [key]: e.target.value }),
    required: true,
  });

  async function submit(e: FormEvent) {
    e.preventDefault();
    setError("");
    try {
      await api("/api/auth/register", form);
      router.push("/");
    } catch (err) {
      setError((err as Error).message);
    }
  }

  return (
    <>
      <h1>Create account</h1>
      <form className="card" onSubmit={submit} style={{ maxWidth: 400 }}>
        <label>Full name<input {...field("fullName")} maxLength={60} /></label>
        <label style={{ marginTop: 10 }}>Email<input type="email" {...field("email")} /></label>
        <label style={{ marginTop: 10 }}>Mobile (10 digits, starts 6-9)<input {...field("phone")} /></label>
        <label style={{ marginTop: 10 }}>Password (8+ characters)<input type="password" {...field("password")} /></label>
        {error && <p className="error">{error}</p>}
        <p><button>Register</button></p>
      </form>
    </>
  );
}
