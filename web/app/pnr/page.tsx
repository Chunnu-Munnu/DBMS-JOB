"use client";

import { useRouter } from "next/navigation";
import { useState, type FormEvent } from "react";

export default function PnrLookup() {
  const [pnr, setPnr] = useState("");
  const router = useRouter();
  const go = (e: FormEvent) => {
    e.preventDefault();
    router.push(`/pnr/${pnr.trim()}`);
  };
  return (
    <>
      <h1>PNR status</h1>
      <form className="card row" onSubmit={go}>
        <label>10-digit PNR
          <input value={pnr} onChange={(e) => setPnr(e.target.value)} pattern="[0-9]{10}" required />
        </label>
        <button>Check status</button>
      </form>
    </>
  );
}
