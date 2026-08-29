"""Build docs/ER_diagram.pdf and docs/Relational_schema.pdf from docs/er-diagram.mmd.

The Mermaid source is the single source of truth: the diagram is rendered from it and
the relational schema document is parsed out of it, so the two can never drift apart.

Requires Google Chrome or Microsoft Edge (used headless to render and print) and one
network fetch of mermaid.js, which is cached in the system temp directory.

    python docs/generate_pdfs.py
"""
import html
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.request

DOCS = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(DOCS, "er-diagram.mmd")
MERMAID_URL = "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.min.js"
BUILD = os.path.join(tempfile.gettempdir(), "railway-docs-build")

TITLE = "Railway Reservation &amp; PNR Management System"
TEAM = ("Aariz Qureshi (PES1UG24CS008)", "Amogh Sharma (PES1UG24CS053)")

CHROME_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "google-chrome", "chromium", "chromium-browser", "microsoft-edge",
]

# Subject areas: name, header colour, row tint, border, member entities.
GROUPS = [
    ("Network",   "#1d4ed8", "#eff6ff", "#bfdbfe",
     ["STATION", "TRAIN", "ROUTE"]),
    ("Inventory", "#047857", "#ecfdf5", "#a7f3d0",
     ["TRAVEL_CLASS", "QUOTA", "COACH", "SEAT", "SCHEDULE", "AVAILABILITY"]),
    ("People",    "#6d28d9", "#f5f3ff", "#ddd6fe",
     ["USER_ACCOUNT", "STAFF"]),
    ("Booking",   "#c2410c", "#fff7ed", "#fed7aa",
     ["BOOKING", "TICKET_PASSENGER", "WAITLIST"]),
    ("Finance",   "#be123c", "#fff1f2", "#fecdd3",
     ["FARE_RULE", "PAYMENT", "CANCELLATION"]),
]

FK_TARGET = {
    "station_code": "STATION", "source_code": "STATION", "dest_code": "STATION",
    "from_station": "STATION", "to_station": "STATION", "train_no": "TRAIN",
    "class_code": "TRAVEL_CLASS", "quota_code": "QUOTA", "coach_id": "COACH",
    "seat_id": "SEAT", "schedule_id": "SCHEDULE", "user_id": "USER_ACCOUNT",
    "booked_by_staff": "STAFF", "pnr": "BOOKING", "passenger_id": "TICKET_PASSENGER",
}

CARD = {"||--|{": "1 : N  (total)", "||--o{": "1 : N  (optional)",
        "||--o|": "1 : 0..1", "||--||": "1 : 1"}

DOMAINS = [
    ("train_type", "EXPRESS, SUPERFAST, RAJDHANI, SHATABDI, PASSENGER, VANDE_BHARAT"),
    ("class_code", "1A, 2A, 3A, SL, CC, 2S"),
    ("quota_code", "GN (general), TQ (tatkal), LD (ladies), SS (senior), PH (divyangjan)"),
    ("booking_status", "CONFIRMED, RAC, WAITLISTED, PARTIAL, CANCELLED"),
    ("current_status", "CNF, RAC, WL, CAN"),
    ("berth_type", "LOWER, MIDDLE, UPPER, SIDE_LOWER, SIDE_UPPER, WINDOW, AISLE"),
    ("queue_type", "RAC, WL"),
    ("role (STAFF)", "CLERK, TTE, ADMIN"),
    ("runs_on", "7 characters of Y / N, Monday to Sunday"),
]

CONSTRAINTS = [
    ("chk_train_ends", "TRAIN", "A train cannot start and end at the same station"),
    ("chk_bk_stations", "BOOKING", "A ticket cannot be booked from a station to itself"),
    ("chk_avl", "AVAILABILITY",
     "0 &le; seats_available &le; total_seats &mdash; overbooking is unrepresentable"),
    ("uq_route_stop", "ROUTE", "A train cannot stop at the same station twice"),
    ("uq_wl_position", "WAITLIST",
     "Two passengers cannot hold the same position in one queue"),
    ("chk_tp_status", "TICKET_PASSENGER",
     "A passenger marked CNF must have a seat allotted"),
    ("chk_pnr_fmt", "BOOKING", "PNR must be exactly 10 digits"),
    ("chk_user_phone", "USER_ACCOUNT",
     "Indian mobile format &mdash; starts 6&ndash;9, exactly 10 digits"),
    ("chk_user_email", "USER_ACCOUNT", "Email must contain @ and a domain part"),
    ("chk_runs_on", "TRAIN", "runs_on must be 7 characters, each Y or N"),
]

MAPPING = [
    ("Strong entity &rarr; relation",
     "STATION, TRAIN, TRAVEL_CLASS, QUOTA, USER_ACCOUNT, STAFF",
     "The entity key becomes the primary key of the relation."),
    ("Weak entity &rarr; owner key + partial key",
     "ROUTE (train_no, seq_no)",
     "A stop has no identity without its train. SEAT uses a surrogate key with "
     "UNIQUE(coach_id, seat_no) as its natural key."),
    ("1 : N relationship &rarr; FK on the N side",
     "COACH.train_no, SEAT.coach_id, SCHEDULE.train_no, BOOKING.user_id",
     "The foreign key sits on the many side; no separate relation is needed."),
    ("Ternary / M:N &rarr; own relation",
     "AVAILABILITY, FARE_RULE",
     "A seat count is meaningful only for SCHEDULE &times; TRAVEL_CLASS &times; QUOTA "
     "together; no pair determines it."),
    ("Multivalued attribute &rarr; relation",
     "TICKET_PASSENGER",
     "One PNR carries up to six passengers, each with an individual seat and status."),
    ("Role names on a recursive relationship",
     "TRAIN.source_code / dest_code, BOOKING.from_station / to_station",
     "One entity set participating twice in the same relationship, distinguished by role."),
    ("Optional participation &rarr; nullable FK",
     "TICKET_PASSENGER.seat_id, BOOKING.booked_by_staff, CANCELLATION.passenger_id",
     "NULL until allotment, NULL for online bookings, NULL when the whole PNR is cancelled."),
    ("Normalization",
     "All 17 relations",
     "In 3NF / BCNF. BOOKING.distance_km and total_fare are deliberate point-in-time "
     "snapshots, not transitive dependencies."),
]


# --------------------------------------------------------------------- helpers
def find_chrome():
    for c in CHROME_CANDIDATES:
        if os.path.isfile(c):
            return c
        found = shutil.which(c)
        if found:
            return found
    sys.exit("Google Chrome or Microsoft Edge is required to render the PDFs.")


def group_of(entity):
    for g in GROUPS:
        if entity in g[4]:
            return g
    return ("Other", "#334155", "#f8fafc", "#e2e8f0", [])


def parse(src):
    """Pull relationships and entity attributes out of the Mermaid source."""
    rels = []
    for line in src.splitlines():
        m = re.match(r'\s*(\w+)\s+(\|\|--\S+)\s+(\w+)\s*:\s*"([^"]*)"', line)
        if m:
            rels.append(m.groups())
    rels = list(dict.fromkeys(rels))

    ents = []
    for m in re.finditer(r"(?m)^[ \t]*(\w+)[ \t]*\{([^}]*)\}", src):
        attrs = []
        for line in m.group(2).strip().splitlines():
            am = re.match(r'(\w+)\s+(\w+)\s*((?:(?:PK|FK|UK)\s*,?\s*)*)(?:"([^"]*)")?\s*$',
                          line.strip())
            if not am:
                continue
            keys = ", ".join(k.strip() for k in (am.group(3) or "").split(",") if k.strip())
            attrs.append((am.group(1), am.group(2), keys, am.group(4) or ""))
        ents.append((m.group(1), attrs))
    return rels, ents


def print_pdf(chrome, html_path, pdf_path, window="1600,1200"):
    subprocess.run([chrome, "--headless", "--disable-gpu", "--no-pdf-header-footer",
                    "--window-size=" + window, "--virtual-time-budget=30000",
                    "--print-to-pdf=" + pdf_path.replace("\\", "/"),
                    html_path.replace("\\", "/")],
                   check=True, capture_output=True)
    print("  wrote %s (%d KB)" % (os.path.relpath(pdf_path, os.path.dirname(DOCS)),
                                  os.path.getsize(pdf_path) // 1024))


# ------------------------------------------------------------------ ER diagram
ER_PAGE = """<!doctype html><html><head><meta charset="utf-8">
<script src="mermaid.min.js"></script>
<style>
@page { margin: 0; }
* { box-sizing: border-box; }
body { margin:0; font-family:"Segoe UI",Inter,system-ui,sans-serif; background:#fff; }
.sheet { padding: 46px 54px 54px; }
.head { display:flex; align-items:flex-end; justify-content:space-between;
        border-bottom:5px solid #0f172a; padding-bottom:18px; margin-bottom:6px; }
h1 { margin:0; font-size:46px; letter-spacing:-.5px; color:#0f172a; }
.sub { margin:8px 0 0; font-size:21px; color:#475569; }
.meta { text-align:right; font-size:17px; color:#475569; line-height:1.7; }
.meta b { color:#0f172a; }
.legend { display:flex; flex-wrap:wrap; gap:14px 26px; margin:22px 0 10px; align-items:center; }
.chip { display:flex; align-items:center; gap:9px; font-size:18px; color:#334155; }
.sw { width:26px; height:16px; border-radius:4px; border:2px solid rgba(0,0,0,.28); }
.notation { margin-top:6px; display:flex; gap:34px; font-size:17px; color:#334155;
            background:#f8fafc; border:1.5px solid #e2e8f0; border-radius:10px; padding:12px 18px; }
.notation code { font-family:Consolas,monospace; color:#0f172a; font-weight:700; }
#out { margin-top:18px; }
#out svg { width:100%; height:auto; max-width:none; }
.label.name .nodeLabel p { color:#fff !important; font-weight:800 !important; letter-spacing:.4px; }
.label.attribute-keys .nodeLabel p { font-weight:700 !important; }
.foot { margin-top:26px; border-top:2px solid #e2e8f0; padding-top:14px; font-size:16px;
        color:#64748b; display:flex; justify-content:space-between; }
</style></head><body>
<div class="sheet">
  <div class="head">
    <div><h1>__TITLE__</h1>
    <p class="sub">Entity&ndash;Relationship Diagram &middot; __NE__ entities &middot; __NR__ relationships</p></div>
    <div class="meta"><b>DBMS Mini Project &mdash; Level 3</b><br>__TEAM__</div>
  </div>
  <div class="legend" id="legend"></div>
  <div class="notation">
    <span><code>||--|{</code> one-to-many, total participation</span>
    <span><code>||--o{</code> one-to-many, optional participation</span>
    <span><code>||--o|</code> one-to-zero-or-one</span>
    <span><code>PK</code> primary key &nbsp; <code>FK</code> foreign key &nbsp; <code>UK</code> unique key</span>
  </div>
  <div id="out"></div>
  <div class="foot"><span>PES University &middot; Department of Computer Science</span>
  <span>Generated from docs/er-diagram.mmd</span></div>
</div>
<script type="text/plain" id="mmd">__MERMAID__</script>
<script>
const GROUPS = __GROUPS__;
document.getElementById('legend').innerHTML = GROUPS.map(g =>
  `<span class="chip"><span class="sw" style="background:${g.color}"></span>${g.name}</span>`).join('');
const groupOf = n => GROUPS.find(g => g.ents.includes(n));

mermaid.initialize({startOnLoad:false, theme:'base',
  themeVariables:{fontFamily:'Segoe UI, Inter, system-ui, sans-serif', fontSize:'15px'},
  er:{fontSize:15, entityPadding:14, useMaxWidth:false}});

(async () => {
  const {svg} = await mermaid.render('erg', document.getElementById('mmd').textContent);
  const out = document.getElementById('out');
  out.innerHTML = svg;
  out.querySelector('svg').removeAttribute('style');

  out.querySelectorAll('g.node').forEach(n => {
    const nm = (n.id || '').replace(/^erg-entity-/, '').replace(/-\\d+$/, '');
    const g = groupOf(nm);
    if (!g) return;
    n.querySelectorAll('.outer-path path').forEach(p => {
      if (p.getAttribute('fill') && p.getAttribute('fill') !== 'none') p.setAttribute('fill', g.color);
      if (p.getAttribute('stroke') && p.getAttribute('stroke') !== 'none') {
        p.setAttribute('stroke', g.color); p.setAttribute('stroke-width', '2');
      }
    });
    n.querySelectorAll('.row-rect-odd path, .row-rect-even path').forEach(p => {
      const even = p.parentNode.classList.contains('row-rect-even');
      if (p.getAttribute('fill') && p.getAttribute('fill') !== 'none')
        p.setAttribute('fill', even ? g.tint : '#ffffff');
      if (p.getAttribute('stroke') && p.getAttribute('stroke') !== 'none') {
        p.setAttribute('stroke', g.line); p.setAttribute('stroke-width', '1');
      }
    });
  });
  out.querySelectorAll('path.relationshipLine').forEach(p => {
    p.setAttribute('stroke', '#334155'); p.setAttribute('stroke-width', '1.6');
  });
  out.querySelectorAll('marker path, marker circle').forEach(m => {
    if (m.getAttribute('fill') !== 'white') m.setAttribute('stroke', '#334155');
  });

  // size the printed page to the rendered content, so nothing is clipped
  const box = document.querySelector('.sheet').getBoundingClientRect();
  const st = document.createElement('style');
  st.textContent = `@page { size: ${Math.ceil(box.width)}px ${Math.ceil(box.height) + 40}px; margin:0; }`;
  document.head.appendChild(st);
})();
</script></body></html>"""


def build_er(chrome, src, rels, ents):
    groups_js = "[%s]" % ",".join(
        "{name:'%s',color:'%s',tint:'%s',line:'%s',ents:[%s]}"
        % (g[0], g[1], g[2], g[3], ",".join("'%s'" % e for e in g[4])) for g in GROUPS)
    page = (ER_PAGE.replace("__TITLE__", TITLE)
                   .replace("__NE__", str(len(ents)))
                   .replace("__NR__", str(len(rels)))
                   .replace("__TEAM__", "<br>".join(TEAM))
                   .replace("__GROUPS__", groups_js)
                   .replace("__MERMAID__", src))
    path = os.path.join(BUILD, "er.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write(page)
    print_pdf(chrome, path, os.path.join(DOCS, "ER_diagram.pdf"), window="3600,3000")


# ----------------------------------------------------------- relational schema
SCHEMA_CSS = """
@page { size: A4; margin: 15mm 14mm 16mm; }
* { box-sizing: border-box; }
body { margin:0; font-family:"Segoe UI",Inter,system-ui,sans-serif; color:#0f172a;
       font-size:9.4pt; line-height:1.45; }
.mono { font-family:Consolas,"SF Mono",monospace; }
.cover { border-bottom:4px solid #0f172a; padding-bottom:12px; margin-bottom:14px;
         display:flex; justify-content:space-between; align-items:flex-end; }
h1 { font-size:22pt; margin:0; letter-spacing:-.4px; }
.cover p { margin:6px 0 0; color:#475569; font-size:10.5pt; }
.who { text-align:right; font-size:8.6pt; color:#475569; line-height:1.6; }
.who b { color:#0f172a; }
h2 { font-size:13.5pt; margin:20px 0 9px; padding-left:10px; border-left:5px solid #0f172a;
     break-after:avoid; }
.stats { display:flex; gap:9px; margin:12px 0 4px; }
.stat { flex:1; border:1.5px solid #e2e8f0; border-radius:9px; padding:9px 11px; background:#f8fafc; }
.stat b { display:block; font-size:17pt; line-height:1.1; }
.stat span { font-size:8pt; color:#64748b; text-transform:uppercase; letter-spacing:.6px; }
.legend { display:flex; flex-wrap:wrap; gap:8px 18px; margin:10px 0 2px; font-size:9pt; color:#334155; }
.chip { display:flex; align-items:center; gap:6px; }
.chip i { width:14px; height:10px; border-radius:3px; display:inline-block; }
.chip em { color:#94a3b8; font-style:normal; }
.grid { column-count:2; column-gap:9mm; margin-top:10px; }
.card { break-inside:avoid; page-break-inside:avoid; display:inline-block; width:100%;
        border:1.4px solid var(--edge); border-radius:9px; overflow:hidden; margin:0 0 6mm; background:#fff; }
.card header { background:var(--c); color:#fff; padding:6px 10px;
               display:flex; justify-content:space-between; align-items:center; }
.card h3 { margin:0; font-size:10.5pt; letter-spacing:.4px; font-family:Consolas,monospace; }
.tag { font-size:7pt; text-transform:uppercase; letter-spacing:.8px; opacity:.85; }
.card table { width:100%; border-collapse:collapse; font-size:8.4pt; }
.card th { background:var(--tint); color:#475569; font-size:7pt; text-transform:uppercase;
           letter-spacing:.6px; text-align:left; padding:4px 8px; border-bottom:1px solid var(--edge); }
.card td { padding:3.4px 8px; border-bottom:.7px solid #f1f5f9; vertical-align:top; }
.card tr:last-child td { border-bottom:none; }
.card tr.pk td { background:var(--tint); }
.an { font-family:Consolas,monospace; font-weight:600; }
.ty { color:#64748b; font-size:7.6pt; font-family:Consolas,monospace; text-transform:uppercase; }
.nt { color:#64748b; font-size:7.6pt; }
.ky { white-space:nowrap; }
.k { display:inline-block; font-size:6.6pt; font-weight:800; padding:1px 4px; border-radius:3px;
     margin-right:2px; letter-spacing:.4px; color:#fff; }
.k-pk { background:#0f172a; } .k-fk { background:var(--c); } .k-uk { background:#64748b; }
.card footer { background:var(--tint); color:#475569; font-size:7.4pt; padding:4px 10px;
               border-top:1px solid var(--edge); }
table.wide { width:100%; border-collapse:collapse; font-size:8.6pt; }
table.wide th { background:#0f172a; color:#fff; text-align:left; padding:6px 9px; font-size:7.4pt;
                text-transform:uppercase; letter-spacing:.6px; }
table.wide td { padding:4.5px 9px; border-bottom:.8px solid #e2e8f0; vertical-align:top; }
table.wide tr:nth-child(even) td { background:#f8fafc; }
table.wide tr { break-inside:avoid; }
.sym { font-family:Consolas,monospace; color:#1d4ed8; font-weight:700; text-align:center; }
.notation { display:flex; gap:8px; margin:10px 0; }
.ncard { flex:1; border:1.4px solid #e2e8f0; border-radius:8px; padding:8px 10px; background:#f8fafc; }
.ncard code { display:block; font-weight:800; color:#1d4ed8; font-size:10pt; }
.ncard span { font-size:8pt; color:#475569; }
.note { background:#fff7ed; border-left:4px solid #f97316; border-radius:0 8px 8px 0;
        padding:9px 12px; font-size:8.8pt; color:#7c2d12; margin-top:12px; break-inside:avoid; }
footer.doc { margin-top:18px; border-top:2px solid #e2e8f0; padding-top:9px;
             font-size:7.8pt; color:#94a3b8; display:flex; justify-content:space-between; }
"""

SCHEMA_PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>Relational Schema</title>
<style>%s</style></head><body>
<div class="cover">
  <div><h1>Relational Schema</h1>
  <p>%s &middot; ER &rarr; relational mapping</p></div>
  <div class="who"><b>DBMS Mini Project &mdash; Level 3</b><br>%s<br>PES University</div>
</div>
<div class="stats">
  <div class="stat"><b>%d</b><span>Relations</span></div>
  <div class="stat"><b>%d</b><span>Attributes</span></div>
  <div class="stat"><b>%d</b><span>Foreign keys</span></div>
  <div class="stat"><b>%d</b><span>Relationships</span></div>
  <div class="stat"><b>3NF</b><span>Normal form</span></div>
</div>
<div class="legend">%s</div>
<h2>1 &nbsp; Relations</h2>
<div class="grid">%s</div>
<h2>2 &nbsp; Relationships and Cardinality</h2>
<div class="notation">%s</div>
<table class="wide"><thead><tr><th>Parent</th><th>Notation</th><th>Child</th>
<th>Cardinality</th><th>Reads as</th></tr></thead><tbody>%s</tbody></table>
<h2>3 &nbsp; ER &rarr; Relational Mapping Rules Applied</h2>
<table class="wide"><thead><tr><th style="width:23%%">Rule</th>
<th style="width:30%%">Where it applies</th><th>Justification</th></tr></thead><tbody>%s</tbody></table>
<h2>4 &nbsp; Domain Constraints</h2>
<table class="wide"><thead><tr><th style="width:24%%">Attribute</th><th>Allowed values</th></tr></thead>
<tbody>%s</tbody></table>
<h2>5 &nbsp; Named Integrity Constraints</h2>
<table class="wide"><thead><tr><th style="width:20%%">Constraint</th>
<th style="width:20%%">Relation</th><th>Rule enforced</th></tr></thead><tbody>%s</tbody></table>
<div class="note"><b>Known limitation.</b> The rule &ldquo;the same physical seat must not be allotted
twice on the same schedule&rdquo; is not expressible as a table constraint: TICKET_PASSENGER holds
<span class="mono">seat_id</span> but reaches the schedule only through BOOKING, and a plain
UNIQUE(seat_id) would wrongly block reuse of that seat on another date. It is enforced by a
BEFORE INSERT trigger in the DML phase, backed by a Redis seat lock during the booking window.</div>
<footer class="doc"><span>Generated from <span class="mono">docs/er-diagram.mmd</span> &mdash; diagram and
schema cannot drift apart.</span><span>PES University &middot; Department of Computer Science</span></footer>
</body></html>"""


def badge(keys):
    return "".join('<span class="k k-%s">%s</span>' % (p.strip().lower(), p.strip())
                   for p in keys.split(",") if p.strip())


def build_schema(chrome, rels, ents):
    cards = []
    for name, attrs in ents:
        g = group_of(name)
        rows = []
        for typ, an, keys, note in attrs:
            if "FK" in keys and FK_TARGET.get(an, name) != name:
                extra = "&rarr; %s" % FK_TARGET[an]
                if note:
                    extra += " &middot; " + html.escape(note)
            else:
                extra = html.escape(note)
            rows.append('<tr%s><td class="an">%s</td><td class="ty">%s</td>'
                        '<td class="ky">%s</td><td class="nt">%s</td></tr>'
                        % (' class="pk"' if "PK" in keys else "", an, typ, badge(keys), extra))
        pk = ", ".join(a[1] for a in attrs if "PK" in a[2])
        nfk = sum(1 for a in attrs if "FK" in a[2])
        cards.append(
            '<section class="card" style="--c:%s;--tint:%s;--edge:%s">'
            '<header><h3>%s</h3><span class="tag">%s</span></header>'
            '<table><thead><tr><th>Attribute</th><th>Type</th><th>Key</th><th>Notes</th></tr>'
            "</thead><tbody>%s</tbody></table>"
            "<footer>PK (%s) &middot; %d attributes &middot; %d foreign key%s</footer></section>"
            % (g[1], g[2], g[3], name, g[0], "".join(rows), pk, len(attrs), nfk,
               "" if nfk == 1 else "s"))

    relrows = "".join(
        '<tr><td class="mono">%s</td><td class="sym">%s</td><td class="mono">%s</td>'
        "<td>%s</td><td>%s</td></tr>" % (a, s, b, CARD.get(s, s), html.escape(lbl))
        for a, s, b, lbl in rels)
    notation = "".join('<div class="ncard"><code>%s</code><span>%s</span></div>' % kv
                       for kv in CARD.items())
    domrows = "".join('<tr><td class="mono">%s</td><td>%s</td></tr>' % d for d in DOMAINS)
    conrows = "".join('<tr><td class="mono">%s</td><td class="mono">%s</td><td>%s</td></tr>' % c
                      for c in CONSTRAINTS)
    maprows = "".join('<tr><td><b>%s</b></td><td class="mono">%s</td><td>%s</td></tr>' % m
                      for m in MAPPING)
    legend = "".join('<span class="chip"><i style="background:%s"></i>%s <em>(%d)</em></span>'
                     % (g[1], g[0], len(g[4])) for g in GROUPS)

    doc = SCHEMA_PAGE % (SCHEMA_CSS, TITLE, "<br>".join(TEAM), len(ents),
                         sum(len(a) for _, a in ents),
                         sum(1 for _, a in ents for x in a if "FK" in x[2]),
                         len(rels), legend, "".join(cards), notation, relrows,
                         maprows, domrows, conrows)
    path = os.path.join(BUILD, "schema.html")
    with open(path, "w", encoding="utf-8") as f:
        f.write(doc)
    print_pdf(chrome, path, os.path.join(DOCS, "Relational_schema.pdf"), window="900,1400")


def main():
    os.makedirs(BUILD, exist_ok=True)
    mermaid = os.path.join(BUILD, "mermaid.min.js")
    if not os.path.exists(mermaid):
        print("  fetching mermaid.js ...")
        urllib.request.urlretrieve(MERMAID_URL, mermaid)

    with open(SRC, encoding="utf-8") as f:
        src = f.read()
    rels, ents = parse(src)
    print("  parsed %d entities, %d relationships" % (len(ents), len(rels)))

    chrome = find_chrome()
    build_er(chrome, src, rels, ents)
    build_schema(chrome, rels, ents)


if __name__ == "__main__":
    main()
