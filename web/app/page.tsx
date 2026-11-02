"use client";

import Link from "next/link";
import { useEffect, useState, type FormEvent } from "react";
import { api } from "@/lib/api";
import type { TrainResult } from "@/lib/search";

type Station = { station_code: string; station_name: string; city: string };

const tomorrow = () => new Date(Date.now() + 86400000).toISOString().slice(0, 10);

export default function SearchPage() {
  const [stations, setStations] = useState<Station[]>([]);
  const [from, setFrom] = useState("SBC");
  const [to, setTo] = useState("NDLS");
  const [date, setDate] = useState(tomorrow());
  const [results, setResults] = useState<TrainResult[] | null>(null);
  const [error, setError] = useState("");
  const [finder, setFinder] = useState("");
  const [matches, setMatches] = useState<Station[]>([]);

  useEffect(() => {
    api<Station[]>("/api/stations").then(setStations).catch((e) => setError(e.message));
  }, []);

  // Full-text station search once three characters are typed.
  useEffect(() => {
    if (finder.trim().length < 3) {
      setMatches([]);
      return;
    }
    api<Station[]>(`/api/stations?q=${encodeURIComponent(finder)}`).then(setMatches).catch(() => setMatches([]));
  }, [finder]);

  async function search(e: FormEvent) {
    e.preventDefault();
    setError("");
    setResults(null);
    try {
      const qs = new URLSearchParams({ from, to, date });
      setResults(await api<TrainResult[]>(`/api/trains/search?${qs}`));
    } catch (err) {
      setError((err as Error).message);
    }
  }

  const stationSelect = (value: string, set: (v: string) => void) => (
    <select value={value} onChange={(e) => set(e.target.value)}>
      {stations.map((s) => (
        <option key={s.station_code} value={s.station_code}>{s.station_name} ({s.station_code})</option>
      ))}
    </select>
  );

  return (
    <>
      <h1>Find a train</h1>
      <form className="card row" onSubmit={search}>
        <label>From {stationSelect(from, setFrom)}</label>
        <label>To {stationSelect(to, setTo)}</label>
        <label>Journey date
          <input type="date" value={date} onChange={(e) => setDate(e.target.value)} required />
        </label>
        <button type="submit">Search</button>
      </form>
      <div className="card">
        <label>Search stations by name or city
          <input value={finder} onChange={(e) => setFinder(e.target.value)} placeholder="e.g. beng, junction, delhi" />
        </label>
        {matches.map((m) => (
          <p key={m.station_code} style={{ margin: "8px 0 0" }}>
            {m.station_name} ({m.station_code}){" "}
            <button type="button" className="secondary" onClick={() => setFrom(m.station_code)}>Set as From</button>{" "}
            <button type="button" className="secondary" onClick={() => setTo(m.station_code)}>Set as To</button>
          </p>
        ))}
      </div>
      {error && <p className="error">{error}</p>}
      {results?.length === 0 && (
        <p className="card">No train runs from {from} to {to} in that direction on this date.</p>
      )}
      {results?.map((t) => (
        <div className="card" key={t.schedule_id}>
          <strong>{t.train_no} {t.train_name}</strong> <span className="badge">{t.train_type}</span>
          <div className="muted">
            Departs {t.departure_time.slice(0, 5)}, arrives {t.arrival_time.slice(0, 5)}
            {t.day_diff > 0 && ` (+${t.day_diff} day)`}, {t.km} km
          </div>
          <div className="classes">
            {t.classes.map((c) => {
              const qs = new URLSearchParams({
                scheduleId: String(t.schedule_id), train: `${t.train_no} ${t.train_name}`,
                from, to, date, classCode: c.class_code, quotaCode: c.quota_code, fare: String(c.fare),
              });
              return (
                <div className="class-tile" key={c.class_code + c.quota_code}>
                  <strong>{c.class_code}</strong> <span className="muted">{c.quota_code}</span>
                  <div>₹{c.fare}</div>
                  <div className={c.seats_available > 0 ? "ok" : "muted"}>
                    {c.seats_available > 0 ? `${c.seats_available} available`
                      : c.rac_available > 0 ? `RAC ${c.rac_available} left`
                      : `Waitlist ${c.waitlist_count}`}
                  </div>
                  <Link className="button" href={`/book?${qs}`}>Book</Link>
                </div>
              );
            })}
          </div>
        </div>
      ))}
    </>
  );
}
