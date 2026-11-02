"use client";

import { useParams } from "next/navigation";
import { useCallback, useEffect, useState } from "react";
import { api } from "@/lib/api";

type Passenger = {
  passenger_id: number; passenger_name: string; age: number; gender: string; current_status: string;
  booking_position: number | null; current_position: number | null;
  coach_code: string | null; seat_no: number | null; berth_type: string | null;
};
type Pnr = {
  pnr: string; booking_status: string; total_fare: number; train_no: string; train_name: string;
  journey_date: string; from_name: string; to_name: string; class_code: string; quota_code: string;
  distance_km: number; canCancel: boolean; passengers: Passenger[];
  history: { changed_at: string; passenger_name: string; old_status: string | null; new_status: string }[];
};
type CancelResult = {
  refund_amount: number; cancelled: number;
  promoted: { passenger_name: string; pnr: string; old_status: string; new_status: string }[];
};

export default function PnrPage() {
  const { pnr } = useParams<{ pnr: string }>();
  const [data, setData] = useState<Pnr | null>(null);
  const [error, setError] = useState("");
  const [result, setResult] = useState<CancelResult | null>(null);
  const [busy, setBusy] = useState(false);

  const load = useCallback(() => {
    api<Pnr>(`/api/pnr/${pnr}`).then(setData).catch((e) => setError(e.message));
  }, [pnr]);
  useEffect(load, [load]);

  async function cancel(passengerId?: number) {
    if (!confirm(passengerId ? "Cancel this passenger?" : "Cancel the whole ticket?")) return;
    setBusy(true);
    setError("");
    try {
      setResult(await api<CancelResult>(`/api/bookings/${pnr}/cancel`, { passengerId, reason: "Cancelled by user" }));
      load();
    } catch (err) {
      setError((err as Error).message);
    }
    setBusy(false);
  }

  if (error && !data) return <p className="error">{error}</p>;
  if (!data) return <p className="muted">Loading...</p>;
  const active = data.passengers.some((p) => p.current_status !== "CAN");

  return (
    <>
      <h1>PNR {data.pnr} <span className={`badge ${data.booking_status}`}>{data.booking_status}</span></h1>
      <div className="card">
        <strong>{data.train_no} {data.train_name}</strong>
        <div className="muted">
          {data.from_name} to {data.to_name}, {data.journey_date}, {data.distance_km} km,
          class {data.class_code}, quota {data.quota_code}. Fare charged ₹{data.total_fare}.
        </div>
      </div>
      {result && (
        <div className="card">
          <p className="ok">Cancelled {result.cancelled} passenger(s). Refund ₹{result.refund_amount}.</p>
          {result.promoted.length > 0 ? (
            <ul>{result.promoted.map((m, i) => (
              <li key={i}>{m.passenger_name} (PNR {m.pnr}) moved from {m.old_status} to {m.new_status}</li>
            ))}</ul>
          ) : <p className="muted">Nobody was waiting in this queue.</p>}
        </div>
      )}
      {error && <p className="error">{error}</p>}
      <div className="card scroll">
        <table>
          <thead><tr><th>Passenger</th><th>Age</th><th>Status</th><th>Seat</th><th>Queue position</th><th /></tr></thead>
          <tbody>
            {data.passengers.map((p) => (
              <tr key={p.passenger_id}>
                <td>{p.passenger_name}</td>
                <td>{p.age}</td>
                <td><span className={`badge ${p.current_status}`}>{p.current_status}</span></td>
                <td>{p.seat_no ? `${p.coach_code}/${p.seat_no} ${p.berth_type}` : "-"}</td>
                <td>{p.current_position ? `${p.current_status} ${p.current_position} (queue no. ${p.booking_position})` : "-"}</td>
                <td>{data.canCancel && p.current_status !== "CAN" && (
                  <button className="secondary" disabled={busy} onClick={() => cancel(p.passenger_id)}>Cancel</button>
                )}</td>
              </tr>
            ))}
          </tbody>
        </table>
        {data.canCancel && active && (
          <p><button className="danger" disabled={busy} onClick={() => cancel()}>Cancel whole ticket</button></p>
        )}
      </div>
      <h2>Status history</h2>
      <div className="card scroll">
        <table>
          <thead><tr><th>When</th><th>Passenger</th><th>Change</th></tr></thead>
          <tbody>
            {data.history.map((h, i) => (
              <tr key={i}>
                <td>{h.changed_at}</td>
                <td>{h.passenger_name}</td>
                <td>{h.old_status ? `${h.old_status} to ${h.new_status}` : `Booked as ${h.new_status}`}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>
    </>
  );
}
