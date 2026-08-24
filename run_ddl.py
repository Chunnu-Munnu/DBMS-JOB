"""Execute ddl_sqlite.sql, then verify the schema was created correctly."""
import os
import sqlite3

BASE = os.path.dirname(os.path.abspath(__file__))
DB = os.path.join(BASE, "railway.db")

if os.path.exists(DB):
    os.remove(DB)

with open(os.path.join(BASE, "ddl_sqlite.sql"), encoding="utf-8") as f:
    ddl = f.read()

con = sqlite3.connect(DB)
con.executescript(ddl)
con.commit()

cur = con.cursor()
tables = [r[0] for r in cur.execute(
    "SELECT name FROM sqlite_master WHERE type='table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name")]
indexes = [r[0] for r in cur.execute(
    "SELECT name FROM sqlite_master WHERE type='index' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name")]

print("TABLES CREATED: %d" % len(tables))
for t in tables:
    ncols = len(list(cur.execute("PRAGMA table_info(%s)" % t)))
    nfks = len(list(cur.execute("PRAGMA foreign_key_list(%s)" % t)))
    print("  %-18s cols=%-3d fks=%d" % (t, ncols, nfks))

print("\nEXPLICIT INDEXES: %d" % len(indexes))
print("  " + ", ".join(indexes))

# Integrity checks -------------------------------------------------------
cur.execute("PRAGMA foreign_keys = ON")
print("\nfk_check   :", cur.execute("PRAGMA foreign_key_check").fetchall() or "PASS (no violations)")
print("integrity  :", cur.execute("PRAGMA integrity_check").fetchone()[0])

# Prove the constraints actually fire ------------------------------------
def expect_fail(label, sql, params=()):
    try:
        cur.execute(sql, params)
        con.rollback()
        print("  %-38s NOT ENFORCED (bad)" % label)
    except sqlite3.Error as e:
        con.rollback()
        print("  %-38s rejected: %s" % (label, e))

print("\nCONSTRAINT SMOKE TEST")
cur.execute("INSERT INTO STATION VALUES ('SBC','KSR Bengaluru','Bengaluru','Karnataka','SWR')")
cur.execute("INSERT INTO STATION VALUES ('NDLS','New Delhi','Delhi','Delhi','NR')")
con.commit()
expect_fail("duplicate station PK",
            "INSERT INTO STATION VALUES ('SBC','X','Y','Z','SR')")
expect_fail("train with source = destination",
            "INSERT INTO TRAIN VALUES ('12628','Karnataka Exp','SUPERFAST','SBC','SBC','YYYYYYY',2444)")
expect_fail("train referencing unknown station",
            "INSERT INTO TRAIN VALUES ('12628','Karnataka Exp','SUPERFAST','SBC','XXXX','YYYYYYY',2444)")
expect_fail("invalid train_type value",
            "INSERT INTO TRAIN VALUES ('12628','Karnataka Exp','BULLET','SBC','NDLS','YYYYYYY',2444)")
expect_fail("negative total_distance",
            "INSERT INTO TRAIN VALUES ('12628','Karnataka Exp','SUPERFAST','SBC','NDLS','YYYYYYY',-5)")
expect_fail("malformed runs_on flags",
            "INSERT INTO TRAIN VALUES ('12628','Karnataka Exp','SUPERFAST','SBC','NDLS','YYYYZZZ',2444)")
expect_fail("bad phone format on USER_ACCOUNT",
            "INSERT INTO USER_ACCOUNT (full_name,email,phone,password_hash) "
            "VALUES ('Amogh','a@b.com','12345','h')")
expect_fail("email without @",
            "INSERT INTO USER_ACCOUNT (full_name,email,phone,password_hash) "
            "VALUES ('Amogh','notanemail','9876543210','h')")

cur.execute("INSERT INTO TRAIN VALUES ('12628','Karnataka Express','SUPERFAST','SBC','NDLS','YYYYYYY',2444)")
con.commit()
expect_fail("two stops at same seq_no",
            "INSERT INTO ROUTE (train_no,seq_no,station_code,dist_from_src) VALUES "
            "('12628',1,'SBC',0),('12628',1,'NDLS',2444)")

print("\nDDL executed successfully -> %s" % DB)
con.close()
