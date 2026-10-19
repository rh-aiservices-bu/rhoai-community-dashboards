# -*- coding: utf-8 -*-
"""Scaffold for the RHOAI monitoring architecture diagram.

HISTORICAL. This produced the FIRST version of
diagrams/rhoai-monitoring-architecture.excalidraw. That file has since
been edited by hand in Excalidraw, and those edits are the source of
truth.

DO NOT RUN THIS over the current diagram. It writes
rhoai-monitoring-architecture.excalidraw from scratch and would discard
every hand edit. It is kept only to show how the first draft was laid
out, and writes to ./scaffold-out/ rather than over the real files.

To change the diagram, open the .excalidraw in https://excalidraw.com,
edit, then re-export both PNG and SVG from Excalidraw itself.
"""
import json, os, random, html

_OUT = "scaffold-out/"
os.makedirs(_OUT, exist_ok=True)

random.seed(575)                      # deterministic seeds -> stable diffs
def nonce(): return random.randint(10**8, 2 * 10**9)

# ---------------------------------------------------------------- palette
GREEN  = ("#b2f2bb", "#2f9e44")
AMBER  = ("#ffe8cc", "#e8820c")
PURPLE = ("#d0bfff", "#6741d9")
PINK   = ("#ffd8d8", "#e03131")
WHITE  = ("#ffffff", "#4a4a6a")
BLACK  = ("#1e1e1e", "#1e1e1e")
DASH   = ("transparent", "#868e96")
INK    = "#1e1e1e"
MUTED  = "#495057"

SHAPES = []      # ordered draw list

def box(x, y, w, h, label, fill=WHITE, size=12, stack=0, bold=False,
        text_color=None):
    SHAPES.append(dict(kind="box", x=x, y=y, w=w, h=h, label=label,
                       bg=fill[0], stroke=fill[1], size=size, stack=stack,
                       bold=bold, dashed=False, radius=6,
                       text_color=text_color or INK))

def frame(x, y, w, h, title=None, size=13):
    SHAPES.append(dict(kind="box", x=x, y=y, w=w, h=h, label=None,
                       bg=DASH[0], stroke=DASH[1], dashed=True, radius=0,
                       size=size, stack=0, bold=False, text_color=INK))
    if title:
        SHAPES.append(dict(kind="text", x=x + w / 2, y=y + 16, text=title,
                           size=size, bold=True, color=INK, anchor="middle"))

def region(x, y, w, h, title, fill, size=14):
    SHAPES.append(dict(kind="box", x=x, y=y, w=w, h=h, label=None,
                       bg=fill[0], stroke=fill[1], dashed=False, radius=4,
                       size=size, stack=0, bold=False, text_color=INK))
    SHAPES.append(dict(kind="text", x=x + w / 2, y=y + 20, text=title,
                       size=size, bold=True, color=INK, anchor="middle"))

def text(x, y, s, size=11, color=MUTED, anchor="middle", bold=False):
    SHAPES.append(dict(kind="text", x=x, y=y, text=s, size=size,
                       color=color, anchor=anchor, bold=bold))

def arrow(pts, label=None, lx=None, ly=None, dashed=False, color=INK):
    SHAPES.append(dict(kind="arrow", pts=pts, dashed=dashed, color=color))
    if label:
        text(lx, ly, label, size=11, color=MUTED)

# ================================================================ layout
W, H = 1700, 1050

# ---- OpenShift cluster -------------------------------------------------
frame(40, 40, 920, 970)
text(132, 72, "Red Hat", size=13, color=INK, anchor="start", bold=False)
text(132, 94, "OpenShift", size=17, color=INK, anchor="start", bold=True)

box(80, 160, 160, 70, "Tempo\nOperator", GREEN)
box(270, 160, 160, 70, "Cluster\nObservability\nOperator", AMBER, size=11)
box(570, 160, 160, 70, "OpenTelemetry\nOperator", PURPLE)

# ---- RHOAI -------------------------------------------------------------
region(70, 260, 860, 580, "RHOAI", PINK)

# monitoring namespace
frame(95, 300, 435, 260)
text(312, 318, "redhat-ods-monitoring", size=11, color=MUTED)

box(110, 334, 120, 62, "Tempo\n(PV, S3, GCS)", GREEN, size=11)
box(250, 334, 105, 62, "Perses", AMBER)
box(375, 334, 140, 62, "Thanos\nQuerier", AMBER)
box(375, 464, 140, 58, "Prometheus\n(PVC)", AMBER, size=11)
box(215, 464, 130, 58, "Alertmanager", AMBER, size=11)

arrow([(445, 396), (445, 464)])
text(360, 424, "RBAC, long-term", size=10, color=MUTED, anchor="end")
text(360, 437, "storage", size=10, color=MUTED, anchor="end")
arrow([(375, 493), (345, 493)])

# operator + collector
text(650, 312, "RHOAI Operator", size=13, color=INK, bold=True)
box(615, 326, 70, 70, "", BLACK)
text(650, 368, "RHOAI", size=10, color="#ffffff")

box(600, 480, 140, 72, "OpenTelemetry\nCollector", PURPLE, size=11)

arrow([(615, 372), (519, 358)], "defines", 566, 352)
arrow([(650, 398), (650, 478)], "defines", 672, 440)

# workloads
box(100, 600, 120, 62, "Perses\nDashboards", WHITE, size=11, stack=2)
box(285, 600, 120, 62, "RHOAI\nComponents", WHITE, size=11, stack=2)
box(285, 700, 120, 62, "User\nWorkloads", WHITE, size=11, stack=2)

arrow([(283, 628), (224, 628)], "embed", 254, 618)
arrow([(407, 614), (598, 498)], "scrape metrics", 520, 596)
arrow([(407, 642), (598, 520)], "push traces", 505, 640)
arrow([(407, 714), (598, 538)], "scrape metrics", 520, 690)
arrow([(407, 742), (598, 548)], "push traces", 505, 744)
arrow([(517, 490), (598, 500)])
text(558, 476, "scrape metrics", size=10, color=MUTED)

# traces back to Tempo
arrow([(604, 552), (230, 570), (170, 398)], "traces", 262, 556)

# ---- partner vendors ---------------------------------------------------
frame(430, 862, 330, 128, "Partner Vendor Metrics Provider", size=11)
box(445, 898, 120, 76, "AMD GPU\nOperator Metrics\nExporter", WHITE, size=10)
box(580, 898, 120, 76, "NVIDIA DCGM\nMetrics\nExporter", WHITE, size=10)
text(725, 940, "• • •", size=14, color=MUTED)
arrow([(672, 554), (672, 860)])
text(684, 690, "scrape metrics,", size=10, color=MUTED, anchor="start")
text(684, 703, "normalize", size=10, color=MUTED, anchor="start")

# ---- Red Hat internal -------------------------------------------------
frame(1020, 200, 640, 345, "Red Hat Infrastructure", size=14)
frame(1045, 248, 275, 275, "Red Hat Observatorium", size=12)
box(1090, 296, 130, 76, "RHOAI\nTelemeter\nInstance", WHITE, size=10)
box(1090, 421, 130, 76, "RHOAI\nObservatorium\nTenant", WHITE, size=10)
arrow([(1155, 374), (1155, 419)])

frame(1360, 248, 280, 275, "Red Hat Dataverse", size=12)
box(1425, 296, 130, 76, "Tableau\n(RH internal\ndashboards)", WHITE, size=10)
box(1425, 421, 130, 76, "Snowflake", WHITE, size=11)
arrow([(1490, 374), (1490, 419)])
arrow([(1423, 459), (1222, 459)], "imports data from", 1322, 448)

# ---- third party -------------------------------------------------------
frame(1020, 625, 310, 200)
text(1175, 648, "Custom 3rd Party", size=13, color=INK, anchor="middle", bold=True)
text(1175, 666, "Observability (optional)", size=13, color=INK, anchor="middle", bold=True)
box(1100, 692, 150, 86, "OpenTelemetry\nProtocol\nReceiver", WHITE, size=10)

# ---- notes from RHOAISTRAT-575 -----------------------------------------
frame(1020, 858, 640, 152)
text(1040, 880, "Design notes (RHOAISTRAT-575, Approved)", size=12,
     color=INK, anchor="start", bold=True)
_n = [
  'otel-collector runs in gateway mode, 2 replicas by default',
  'Discovery: label monitoring.opendatahub.io/scrape="true" on Service/PodMonitors',
  'Metrics and traces retained 90 days by default, configurable',
  'Thanos Querier fronted by kube-rbac-proxy + prom-label-proxy (namespace-scoped)',
  'Tempo: monolithic mode on PV, microservices mode on object storage',
]
for _i, _s in enumerate(_n):
    text(1040, 902 + _i * 19, "\u2022  " + _s, size=11, color=MUTED,
         anchor="start")

# ---- exports -----------------------------------------------------------
arrow([(742, 496), (900, 440), (1088, 330)])
text(880, 404, "remote write metrics", size=10, color=MUTED)
text(880, 418, "authn: cluster pull secret", size=10, color=MUTED)
arrow([(742, 530), (920, 600), (1098, 712)])
text(878, 632, "export via OTLP", size=10, color=MUTED)

# ====================================================== excalidraw emit
def ex_base(t, x, y, w, h, bg, stroke, dashed, radius):
    return {
        "id": f"e{nonce()}", "type": t, "x": x, "y": y, "width": w,
        "height": h, "angle": 0, "strokeColor": stroke,
        "backgroundColor": bg, "fillStyle": "solid", "strokeWidth": 1.5,
        "strokeStyle": "dashed" if dashed else "solid", "roughness": 0,
        "opacity": 100, "groupIds": [], "frameId": None,
        "roundness": {"type": 3} if radius else None, "seed": nonce(),
        "version": 1, "versionNonce": nonce(), "isDeleted": False,
        "boundElements": [], "updated": 1, "link": None, "locked": False,
    }

def ex_text(s, x, y, size, color, align="center", container=None, w=None):
    lines = s.split("\n")
    tw = w or max(len(l) for l in lines) * size * 0.58
    th = len(lines) * size * 1.25
    e = {
        "id": f"t{nonce()}", "type": "text", "x": x, "y": y, "width": tw,
        "height": th, "angle": 0, "strokeColor": color,
        "backgroundColor": "transparent", "fillStyle": "solid",
        "strokeWidth": 1, "strokeStyle": "solid", "roughness": 0,
        "opacity": 100, "groupIds": [], "frameId": None, "roundness": None,
        "seed": nonce(), "version": 1, "versionNonce": nonce(),
        "isDeleted": False, "boundElements": [], "updated": 1, "link": None,
        "locked": False, "fontSize": size, "fontFamily": 2, "text": s,
        "textAlign": align, "verticalAlign": "middle",
        "containerId": container, "originalText": s, "lineHeight": 1.25,
        "autoResize": True,
    }
    return e

els = []
for s in SHAPES:
    if s["kind"] == "box":
        for i in range(s["stack"], 0, -1):            # stack shadows
            off = 5 * i
            sh = ex_base("rectangle", s["x"] + off, s["y"] - off, s["w"],
                         s["h"], s["bg"], s["stroke"], False, s["radius"])
            els.append(sh)
        r = ex_base("rectangle", s["x"], s["y"], s["w"], s["h"], s["bg"],
                    s["stroke"], s["dashed"], s["radius"])
        els.append(r)
        if s["label"]:
            t = ex_text(s["label"], s["x"] + 6, s["y"] + 6, s["size"],
                        s["text_color"], container=r["id"], w=s["w"] - 12)
            r["boundElements"] = [{"type": "text", "id": t["id"]}]
            els.append(t)
    elif s["kind"] == "text":
        lines = s["text"].split("\n")
        tw = max(len(l) for l in lines) * s["size"] * 0.58
        x = {"middle": s["x"] - tw / 2, "start": s["x"],
             "end": s["x"] - tw}[s.get("anchor", "middle")]
        els.append(ex_text(s["text"], x, s["y"] - s["size"] * 0.75,
                           s["size"], s["color"],
                           align={"middle": "center", "start": "left",
                                  "end": "right"}[s.get("anchor", "middle")]))
    elif s["kind"] == "arrow":
        pts = s["pts"]
        x0, y0 = pts[0]
        rel = [[round(px - x0, 2), round(py - y0, 2)] for px, py in pts]
        xs = [p[0] for p in rel]; ys = [p[1] for p in rel]
        a = ex_base("arrow", x0, y0, max(xs) - min(xs), max(ys) - min(ys),
                    "transparent", s["color"], s["dashed"], False)
        a.update({"points": rel, "lastCommittedPoint": None,
                  "startBinding": None, "endBinding": None,
                  "startArrowhead": None, "endArrowhead": "arrow",
                  "elbowed": False})
        els.append(a)

doc = {"type": "excalidraw", "version": 2, "source": "rhoai-dashboards-as-code",
       "elements": els,
       "appState": {"gridSize": None, "viewBackgroundColor": "#ffffff"},
       "files": {}}

with open(_OUT + "rhoai-monitoring-architecture.excalidraw", "w") as f:
    json.dump(doc, f, indent=2)

# ============================================================= svg emit
def esc(s): return html.escape(s, quote=True)

out = [
 f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
 f'viewBox="0 0 {W} {H}" font-family="Helvetica, Arial, sans-serif">',
 '<defs><marker id="ah" viewBox="0 0 10 10" refX="9" refY="5" '
 'markerWidth="7" markerHeight="7" orient="auto-start-reverse">'
 '<path d="M0,1 L9,5 L0,9" fill="none" stroke="#1e1e1e" stroke-width="1.6"/>'
 '</marker></defs>',
 f'<rect width="{W}" height="{H}" fill="#ffffff"/>',
]

for s in SHAPES:
    if s["kind"] == "box":
        for i in range(s["stack"], 0, -1):
            off = 5 * i
            out.append(
              f'<rect x="{s["x"]+off}" y="{s["y"]-off}" width="{s["w"]}" '
              f'height="{s["h"]}" rx="{s["radius"]}" fill="{s["bg"]}" '
              f'stroke="{s["stroke"]}" stroke-width="1.5"/>')
        da = ' stroke-dasharray="7 5"' if s["dashed"] else ''
        out.append(
          f'<rect x="{s["x"]}" y="{s["y"]}" width="{s["w"]}" '
          f'height="{s["h"]}" rx="{s["radius"]}" fill="{s["bg"]}" '
          f'stroke="{s["stroke"]}" stroke-width="1.5"{da}/>')
        if s["label"]:
            lines = s["label"].split("\n")
            cy = s["y"] + s["h"] / 2 - (len(lines) - 1) * s["size"] * 0.62
            for i, ln in enumerate(lines):
                out.append(
                  f'<text x="{s["x"]+s["w"]/2}" y="{cy + i*s["size"]*1.25}" '
                  f'font-size="{s["size"]}" fill="{s["text_color"]}" '
                  f'text-anchor="middle" dominant-baseline="middle">'
                  f'{esc(ln)}</text>')
    elif s["kind"] == "text":
        anc = {"middle": "middle", "start": "start", "end": "end"}[
            s.get("anchor", "middle")]
        fw = ' font-weight="700"' if s.get("bold") else ''
        out.append(
          f'<text x="{s["x"]}" y="{s["y"]}" font-size="{s["size"]}" '
          f'fill="{s["color"]}" text-anchor="{anc}"{fw}>{esc(s["text"])}</text>')
    elif s["kind"] == "arrow":
        d = "M " + " L ".join(f"{px},{py}" for px, py in s["pts"])
        da = ' stroke-dasharray="6 4"' if s["dashed"] else ''
        out.append(
          f'<path d="{d}" fill="none" stroke="{s["color"]}" '
          f'stroke-width="1.6" marker-end="url(#ah)"{da}/>')

# Red Hat hat, exact paths from the shared brand asset
HAT1 = ("M127 90.2c12.5 0 30.6-2.6 30.6-17.5a12.678 12.678 0 00-.3-3.4L149.8 "
        "37c-1.7-7.1-3.2-10.3-15.7-16.6-9.7-5-30.8-13.1-37.1-13.1-5.8 0-7.5 "
        "7.5-14.4 7.5-6.7 0-11.6-5.6-17.9-5.6-6 0-9.9 4.1-12.9 12.5 0 0-8.4 "
        "23.7-9.5 27.2a4.216 4.216 0 00-.3 1.9c0 9.2 36.3 39.4 85 39.4zm32.5"
        "-11.4c1.7 8.2 1.7 9.1 1.7 10.1 0 14-15.7 21.8-36.4 21.8-46.8 0-87.7"
        "-27.4-87.7-45.5a17.535 17.535 0 011.5-7.3C21.8 58.8 0 61.8 0 81c0 "
        "31.5 74.6 70.3 133.7 70.3 45.3 0 56.7-20.5 56.7-36.6-.1-12.8-11-27.3"
        "-30.9-35.9z")
HAT2 = ("M159.5 78.8c1.7 8.2 1.7 9.1 1.7 10.1 0 14-15.7 21.8-36.4 21.8-46.8 0"
        "-87.7-27.4-87.7-45.5a17.535 17.535 0 011.5-7.3l3.7-9.1a4.877 4.877 0 "
        "00-.3 2c0 9.2 36.3 39.4 85 39.4 12.5 0 30.6-2.6 30.6-17.5a12.678 "
        "12.678 0 00-.3-3.4z")
out.append('<g transform="translate(72,56) scale(0.28)">'
           f'<path d="{HAT1}" fill="#e00"/><path d="{HAT2}" fill="#1e1e1e"/></g>')
out.append("</svg>")

with open(_OUT + "rhoai-monitoring-architecture.svg", "w") as f:
    f.write("\n".join(out))

print(f"excalidraw elements: {len(els)}")
print(f"svg bytes: {len(chr(10).join(out))}")
