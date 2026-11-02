import { NextResponse } from "next/server";

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

const UNAVAILABLE = new Set([
  "ECONNREFUSED", "ETIMEDOUT", "ECONNRESET", "ENOTFOUND", "PROTOCOL_CONNECTION_LOST",
  "ER_ACCESS_DENIED_ERROR", "ER_CON_COUNT_ERROR", "ER_LOCK_DEADLOCK", "ER_LOCK_WAIT_TIMEOUT",
  "ER_QUERY_TIMEOUT",
]);

// Turns a driver error into a status and a message that is safe to show a user.
export function describeError(err: unknown): { status: number; message: string } {
  if (err instanceof ApiError) return { status: err.status, message: err.message };

  const e = err as { code?: string; sqlMessage?: string };
  const code = e.code ?? "";
  if (UNAVAILABLE.has(code)) {
    return { status: 503, message: "The database is busy or unavailable. Nothing was changed; please try again." };
  }
  switch (code) {
    case "ER_SIGNAL_EXCEPTION": // SIGNAL from our procedures and triggers: written for users
      return { status: 422, message: e.sqlMessage ?? "Request rejected" };
    case "ER_DUP_ENTRY":
      return { status: 409, message: duplicateMessage(e.sqlMessage ?? "") };
    case "ER_CHECK_CONSTRAINT_VIOLATED":
      return { status: 400, message: `Invalid data: ${e.sqlMessage ?? "a rule was violated"}` };
    case "ER_NO_REFERENCED_ROW_2":
    case "ER_ROW_IS_REFERENCED_2":
      return { status: 400, message: "This refers to a record that does not exist or is still in use" };
    case "ER_DATA_TOO_LONG":
    case "WARN_DATA_TRUNCATED":
    case "ER_TRUNCATED_WRONG_VALUE":
    case "ER_TRUNCATED_WRONG_VALUE_FOR_FIELD":
    case "ER_BAD_NULL_ERROR":
    case "ER_WARN_DATA_OUT_OF_RANGE":
      return { status: 400, message: "One of the values is missing or not valid" };
    default:
      console.error("Unexpected error:", err);
      return { status: 500, message: "Something went wrong on our side" };
  }
}

function duplicateMessage(sql: string): string {
  if (sql.includes("email")) return "That email is already registered";
  if (sql.includes("phone")) return "That phone number is already registered";
  if (sql.includes("uq_tp_name")) return "Two passengers on one ticket cannot have the same name";
  if (sql.includes("uq_schedule")) return "This train is already scheduled on that date";
  if (sql.includes("uq_fare")) return "A fare rule already starts on that date";
  return "This record already exists";
}

type Handler<C> = (req: Request, ctx: C) => Promise<Response>;

// Wraps every route so no error escapes as a raw stack trace.
export function route<C>(handler: Handler<C>): Handler<C> {
  return async (req, ctx) => {
    try {
      return await handler(req, ctx);
    } catch (err) {
      const { status, message } = describeError(err);
      return NextResponse.json({ error: message }, { status });
    }
  };
}
