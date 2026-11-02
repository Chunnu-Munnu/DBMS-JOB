"use client";

import { useState, type FormEvent } from "react";
import { api } from "@/lib/api";

type Row = {
  pnr: string; class_code: string; coach_code: string | null; seat_no: number | null; berth_type: string | null;
  passenger_name: string; age: number; gender: string; current_status: string;
  current_position: number | null; from_station: string; to_station: string;
};

export default function TtePage() {
  const [train, setTrain] = useState("12627");
  const [date, setDate] = useState(new Date(Date.now() + 20 * 864e5).toISOString().slice(0, 10));
  const [rows, setRows] = useState<Row[] | null>(null);
  const [error, setError] = useState("");

  async function load(e: FormEvent) {
    e.preventDefault();
    setError("");
    try {
      const qs = new URLSearchParams({ train, date });
      setRows((await api<{ passengers: Row[] }>(`/api/tte/chart?${qs}`)).passengers);
    } catch (err) {
      setError((err as Error).message);
    }
  }

  return (
    <>
      <h1>Examiner chart</h1>
      <form className="card row" onSubmit={load}>
        <label>Train number<input value={train} onChange={(e) => setTrain(e.target.value)} required /></label>
        <label>Journey date<input type="date" value={date} onChange={(e) => setDate(e.target.value)} required /></label>
        <button>Load chart</button>
      </form>
      {error && <p className="error">{error}</p>}
      {rows?.length === 0 && <p className="card">No passengers on this run.</p>}
      {rows && rows.length > 0 && (
        <div className="card scroll">
          <table>
            <thead><tr><th>Class</th><th>Seat</th><th>Passenger</th><th>Journey</th><th>PNR</th><th>Status</th></tr></thead>
            <tbody>
              {rows.map((r, i) => (
                <tr key={i}>
                  <td>{r.class_code}</td>
                  <td>{r.seat_no ? `${r.coach_code}/${r.seat_no} ${r.berth_type}` : "-"}</td>
                  <td>{r.passenger_name}, {r.age}{r.gender}</td>
                  <td>{r.from_station} to {r.to_station}</td>
                  <td>{r.pnr}</td>
                  <td><span className={`badge ${r.current_status}`}>{r.current_status}{r.current_position ? ` ${r.current_position}` : ""}</span></td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </>
  );
}
