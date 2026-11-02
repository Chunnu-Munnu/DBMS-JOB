"use client";

import { useRouter, useSearchParams } from "next/navigation";
import { Suspense, useEffect, useState, type FormEvent } from "react";
import { api } from "@/lib/api";

type Passenger = { name: string; age: string; gender: string; berth_pref: string };
const blank: Passenger = { name: "", age: "", gender: "M", berth_pref: "NONE" };

function BookForm() {
  const q = useSearchParams();
  const router = useRouter();
  const [role, setRole] = useState<string | null>(null);
  const [checked, setChecked] = useState(false);
  const [passengers, setPassengers] = useState<Passenger[]>([{ ...blank }]);
  const [mode, setMode] = useState("UPI");
  const [customerEmail, setCustomerEmail] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  useEffect(() => {
    api<{ role: string } | null>("/api/auth/me").then((u) => {
      setRole(u?.role ?? null);
      setChecked(true);
    });
  }, []);

  const change = (i: number, key: keyof Passenger, value: string) =>
    setPassengers((list) => list.map((p, n) => (n === i ? { ...p, [key]: value } : p)));

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      const res = await api<{ pnr: string }>("/api/bookings", {
        scheduleId: Number(q.get("scheduleId")),
        from: q.get("from"), to: q.get("to"),
        classCode: q.get("classCode"), quotaCode: q.get("quotaCode"),
        mode, customerEmail,
        passengers: passengers.map((p) => ({ ...p, age: Number(p.age) })),
      });
      router.push(`/pnr/${res.pnr}`);
    } catch (err) {
      setError((err as Error).message);
      setBusy(false);
    }
  }

  if (checked && !role) {
    return <p className="card">Please <a href="/login">log in</a> to book a ticket.</p>;
  }
  const fare = Number(q.get("fare") ?? 0);

  return (
    <>
      <h1>Book ticket</h1>
      <div className="card">
        <strong>{q.get("train")}</strong>
        <div className="muted">
          {q.get("from")} to {q.get("to")} on {q.get("date")}, class {q.get("classCode")}, quota {q.get("quotaCode")}
        </div>
      </div>
      <form className="card" onSubmit={submit}>
        {role && role !== "PASSENGER" && (
          <label>Passenger account email (counter booking)
            <input type="email" value={customerEmail} onChange={(e) => setCustomerEmail(e.target.value)} required />
          </label>
        )}
        {passengers.map((p, i) => (
          <div className="row" key={i} style={{ marginBottom: 10 }}>
            <label>Name
              <input value={p.name} onChange={(e) => change(i, "name", e.target.value)} required maxLength={60} />
            </label>
            <label>Age
              <input type="number" min={0} max={120} value={p.age} onChange={(e) => change(i, "age", e.target.value)} required />
            </label>
            <label>Gender
              <select value={p.gender} onChange={(e) => change(i, "gender", e.target.value)}>
                <option value="M">Male</option><option value="F">Female</option><option value="O">Other</option>
              </select>
            </label>
            <label>Berth
              <select value={p.berth_pref} onChange={(e) => change(i, "berth_pref", e.target.value)}>
                {["NONE", "LOWER", "MIDDLE", "UPPER", "SIDE_LOWER", "SIDE_UPPER"].map((b) => <option key={b}>{b}</option>)}
              </select>
            </label>
            {passengers.length > 1 && (
              <button type="button" className="secondary"
                onClick={() => setPassengers((l) => l.filter((_, n) => n !== i))}>Remove</button>
            )}
          </div>
        ))}
        {passengers.length < 6 && (
          <button type="button" className="secondary" onClick={() => setPassengers((l) => [...l, { ...blank }])}>
            Add passenger
          </button>
        )}
        <div className="row" style={{ marginTop: 12 }}>
          <label>Payment (simulated)
            <select value={mode} onChange={(e) => setMode(e.target.value)}>
              {["UPI", "CARD", "NETBANKING", "WALLET", "CASH"].map((m) => <option key={m}>{m}</option>)}
            </select>
          </label>
          <div><strong>Total ₹{(fare * passengers.length).toFixed(2)}</strong></div>
          <button disabled={busy}>{busy ? "Booking..." : "Pay and book"}</button>
        </div>
        {error && <p className="error">{error}</p>}
      </form>
    </>
  );
}

export default function BookPage() {
  return <Suspense><BookForm /></Suspense>;
}
