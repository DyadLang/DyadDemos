"""Unit tests for layout_report's geometry: python3 -m unittest tools/layout-report/test_layout_report.py"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import layout_report as lr  # noqa: E402

BLOCK = ('<g filter="url(#drop-shadow)" transform="translate({tx} {ty}) rotate(0) scale(0.1 0.1)" '
         'transform-origin="center center"><svg viewBox="0 0 1000 1000">'
         '<text x="500" y="1100" font-size="200" dominant-baseline="central" text-anchor="middle">{name}</text>'
         '</svg></g>')
WIRE = '<path d="{d}" fill="transparent" stroke="rgb(0,0,127)"/>'


def svg(blocks, wires, extra=""):
    body = "".join(BLOCK.format(tx=x - 500, ty=y - 500, name=n) for n, x, y in blocks)
    body += "".join(WIRE.format(d=d) for d in wires)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">{body}{extra}</svg>'


class Geometry(unittest.TestCase):
    def test_block_box_and_label(self):
        dg = lr.parse_svg(svg([("a", 100, 200)], []))
        b = dg.blocks[0]
        self.assertEqual(b.name, "a")
        self.assertEqual(tuple(round(v, 6) for v in b.box), (50, 150, 150, 250))
        (_t, lb), = b.labels
        self.assertAlmostEqual((lb[1] + lb[3]) / 2, 260)  # 10 units below the box

    def test_crossing_touch_overlap(self):
        # a: blocks left/right, wires: horizontal and vertical crossing, one T-touch, one shared run
        wires = ["M 0 100 L 400 100", "M 200 0 L 200 300",          # cross at (200,100)
                 "M 300 300 L 300 100",                              # ends on wire 1: false junction
                 "M 0 400 L 300 400", "M 100 400 L 400 400 L 400 500"]  # collinear shared run
        m, _ = lr.compute_metrics(lr.parse_svg(svg([], wires)))
        self.assertEqual(m["crossings"], 1)
        self.assertEqual(m["false_junctions"], 1)
        self.assertEqual(m["overlap_runs"], 1)
        self.assertAlmostEqual(m["overlap_len"], 200)

    def test_same_net_is_exempt(self):
        # two wires from one pin crossing a third wire's path never count against each other
        wires = ["M 0 0 L 100 0 L 100 200", "M 0 0 L 0 100 L 200 100"]
        m, _ = lr.compute_metrics(lr.parse_svg(svg([], wires)))
        self.assertEqual(m["nets"], 1)
        self.assertEqual(m["crossings"], 0)

    def test_through_block_diagonal_bends(self):
        blocks = [("src", 100, 100), ("mid", 400, 100), ("dst", 700, 100)]
        wires = ["M 150 100 L 650 100",            # straight through `mid`
                 "M 150 120 L 300 300 L 650 300"]  # one diagonal segment, one bend
        m, d = lr.compute_metrics(lr.parse_svg(svg(blocks, wires)))
        self.assertEqual(m["wire_through_block"], 1)
        self.assertEqual(d["through_block"], ["src->dst through mid"])
        self.assertEqual(m["diagonal_segments"], 1)
        self.assertEqual(m["bends_max"], 1)

    def test_connect_route_status(self):
        block = '''
  connect(a.y, b.u) {"Dyad": {"edges": [{"S": 1, "M": [], "E": 2}]}}
  connect(a.y, c.u)
  connect(b.y, c.v) [{"Dyad": {"edges": [{"S": 1, "M": [], "E": 2}]}}]
  connect(d.y, e.u, f.u) {^bus}
  for i in 1:3
    connect(g[i].y, h[i].u)
  end
metadata {"Dyad": {"_links": {"bus": {"Dyad": {"junctions": [{"x": 1, "y": 2}], "edges": []}}}}}
'''
        total, missing, arms, looped = lr.connect_route_status(block)
        self.assertEqual((total, missing, arms, looped), (4, 1, 6, 1))


CROSS = ["M 0 100 L 400 100", "M 200 0 L 200 300"]  # two wires crossing at (200, 100)


def metrics(body):
    return lr.compute_metrics(lr.parse_svg(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">{body}</svg>'))[0]


class Transforms(unittest.TestCase):
    def test_translating_a_wire_away_removes_the_crossing(self):
        self.assertEqual(metrics("".join(WIRE.format(d=d) for d in CROSS))["crossings"], 1)
        moved_group = WIRE.format(d=CROSS[0]) + f'<g transform="translate(1000 0)">{WIRE.format(d=CROSS[1])}</g>'
        self.assertEqual(metrics(moved_group)["crossings"], 0)
        moved_path = WIRE.format(d=CROSS[0]) + WIRE.format(d=CROSS[1]).replace("<path ", '<path transform="translate(0 500)" ')
        self.assertEqual(metrics(moved_path)["crossings"], 0)

    def test_wires_inside_a_group_are_still_wires(self):
        m = metrics("<g>" + "".join(WIRE.format(d=d) for d in CROSS) + "</g>")
        self.assertEqual((m["blocks"], m["ports"], m["wires"], m["crossings"]), (0, 0, 2, 1))

    def test_nested_transforms_compose(self):
        # a nested viewport scaling 100 -> 200 units around scale(2): wire coordinates x4
        body = ('<svg x="0" y="0" width="200" height="200" viewBox="0 0 100 100"><g transform="scale(2)">'
                + WIRE.format(d="M 0 10 L 50 10") + "</g></svg>")
        dg = lr.parse_svg(f'<svg xmlns="http://www.w3.org/2000/svg">{body}</svg>')
        self.assertEqual([tuple(round(v, 6) for v in p) for p in dg.wires[0].pts], [(0, 40), (200, 40)])
        dg = lr.parse_svg('<svg xmlns="http://www.w3.org/2000/svg"><g transform="matrix(0 1 -1 0 0 0)">'
                          '<circle cx="10" cy="0" r="2"/></g></svg>')
        self.assertEqual([tuple(round(v, 6) for v in p) for p in dg.junctions], [(0, 10)])

    def test_block_inside_a_transformed_group(self):
        dg = lr.parse_svg(svg([], [], extra=f'<g transform="translate(1000 0)">{BLOCK.format(tx=-400, ty=-300, name="a")}</g>'))
        self.assertEqual(tuple(round(v, 6) for v in dg.blocks[0].box), (1050, 150, 1150, 250))

    def test_wires_wrapped_in_a_group_and_svg_are_still_wires(self):
        # a <g> wrapping an <svg> is only a block when the svg holds icon art; wires keep it a plain group
        wires = "".join(WIRE.format(d=d) for d in CROSS)
        for inner in ('<svg viewBox="0 0 1000 1000">', '<svg x="0" y="0" width="1000" height="1000">', "<svg>"):
            m = metrics(f"<g>{inner}{wires}</svg></g>")
            self.assertEqual((m["blocks"], m["ports"], m["wires"], m["crossings"]), (0, 0, 2, 1), inner)
        # the nested viewport still maps the wires: 100 user units drawn at 1000
        dg = lr.parse_svg('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000"><g><svg viewBox="0 0 100 100">'
                          + WIRE.format(d="M 0 10 L 50 10") + "</svg></g></svg>")
        self.assertEqual([tuple(round(v, 6) for v in p) for p in dg.wires[0].pts], [(0, 100), (500, 100)])
        # a real block next to the wires is still a block
        m = metrics(f'<g>{BLOCK.format(tx=-400, ty=-300, name="a")}<svg viewBox="0 0 1000 1000">{wires}</svg></g>')
        self.assertEqual((m["blocks"], m["wires"], m["crossings"]), (1, 2, 1))

    def test_icon_svg_transform_moves_block_label_and_port(self):
        plain = lr.parse_svg(svg([("a", 100, 200)], []))
        moved = lr.parse_svg(svg([("a", 100, 200)], []).replace('<svg viewBox="0 0 1000 1000">',
                                                               '<svg transform="translate(1000 0)" viewBox="0 0 1000 1000">'))
        shift = lambda bb: tuple(round(v, 6) for v in (bb[0] + 100, bb[1], bb[2] + 100, bb[3]))  # 1000 icon units x 0.1
        self.assertEqual(tuple(round(v, 6) for v in moved.blocks[0].box), shift(plain.blocks[0].box))
        self.assertEqual(tuple(round(v, 6) for v in moved.blocks[0].labels[0][1]), shift(plain.blocks[0].labels[0][1]))
        port = BLOCK.replace('filter="url(#drop-shadow)" ', "")
        dg = lr.parse_svg(svg([], [], extra=port.replace("<svg ", '<svg transform="translate(1000 0)" ').format(tx=-400, ty=-300, name="p")))
        self.assertTrue(dg.blocks[0].is_port)
        self.assertEqual(tuple(round(v, 6) for v in dg.blocks[0].box), (150, 150, 250, 250))
        # a label's own transform, and a free label's
        dg = lr.parse_svg(svg([("a", 100, 200)], []).replace("<text ", '<text transform="translate(0 1000)" '))
        self.assertAlmostEqual((dg.blocks[0].labels[0][1][1] + dg.blocks[0].labels[0][1][3]) / 2, 360)
        dg = lr.parse_svg(svg([], [], extra='<g transform="translate(5 0)"><text x="10" y="20" font-size="10" '
                                            'dominant-baseline="central" transform="translate(100 0)">t</text></g>'))
        self.assertEqual(tuple(round(v, 6) for v in dg.free_labels[0][1]), (115, 15, 121, 25))

    def test_unsupported_transforms_are_rejected(self):
        for t in ("skewX(10)", "skewY(5)", "translate(1 0) skewX(10)", "rotate(1 2)", "matrix(1 0 0 1)", "translate(a)", "bogus"):
            for body in (f'<g transform="{t}">' + WIRE.format(d=CROSS[0]) + "</g>",
                         WIRE.format(d=CROSS[0]).replace("<path ", f'<path transform="{t}" '),
                         BLOCK.format(tx=0, ty=0, name="a").replace("<svg ", f'<svg transform="{t}" '),
                         BLOCK.format(tx=0, ty=0, name="a").replace("<text ", f'<text transform="{t}" ')):
                with self.assertRaises(lr.UnsupportedSVG, msg=body):
                    lr.parse_svg(f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">{body}</svg>')

    def test_unsupported_structures_are_rejected(self):
        for body in ('<svg viewBox="0 0 10 10"><path d="M 0 0 L 5 0" fill="transparent"/></svg>',
                     '<use href="#w"/>'):
            with self.assertRaises(lr.UnsupportedSVG):
                lr.parse_svg(f'<svg xmlns="http://www.w3.org/2000/svg">{body}</svg>')


class Waypoints(unittest.TestCase):
    def test_collinear_waypoint_at_a_crossing(self):
        for wires in (["M 0 100 L 200 100 L 400 100", CROSS[1]],
                      ["M 0 100 L 200 100 L 200 100 L 400 100", "M 200 0 L 200 100 L 200 300"]):
            m, _ = lr.compute_metrics(lr.parse_svg(svg([], wires)))
            self.assertEqual((m["crossings"], m["false_junctions"]), (1, 0), wires)

    def test_split_shared_run_counts_once(self):
        for b in ("M 100 400 L 200 400 L 400 400 L 400 500",   # collinear waypoint inside the run
                  "M 100 400 L 250 400 L 150 400 L 150 500"):  # the run doubles back on itself
            m, _ = lr.compute_metrics(lr.parse_svg(svg([], ["M 0 400 L 300 400", b])))
            self.assertEqual(m["overlap_runs"], 1, b)

    def test_normalize_polyline(self):
        self.assertEqual(lr.normalize_polyline([(0, 0), (0, 0), (5, 0), (10, 0), (10, 5), (10, 10)]),
                         [(0, 0), (10, 0), (10, 10)])
        self.assertEqual(lr.normalize_polyline([(0, 0), (10, 0), (5, 0)]), [(0, 0), (10, 0), (5, 0)])


# a 4 x 2 component with one connector on its right edge, at t = 0.5: local offset (2, 0.5)
COMP = {"id": "A", "width": 4, "height": 2, "connectors": [{"id": "p", "edge": "right", "position": 0.5, "direction": "none"}]}


class D4(unittest.TestCase):
    def test_all_eight_states(self):
        # dyad-layout rust/core/src/d4.rs: flip first (flipH: y -> -y, flipV: x -> -x), then rotate (r90: (x, y) -> (-y, x))
        want = {"identity": (2, 0.5), "r90": (-0.5, 2), "r180": (-2, -0.5), "r270": (0.5, -2),
                "flipH": (2, -0.5), "flipV": (-2, 0.5), "flipH_r90": (0.5, 2), "flipV_r90": (-0.5, -2)}
        self.assertEqual(set(want), set(lr.D4_PTS))
        for state, xy in want.items():
            self.assertEqual(lr.connector_offset(COMP, "p", state), xy, state)

    def test_unknown_state_is_an_error(self):
        for bad in ("flipHR90", "flipVR90", "r45"):
            with self.assertRaises(ValueError):
                lr.connector_offset(COMP, "p", bad)
        prob = problem([COMP], [], {"A": {"initialPosition": {"x": 2, "y": 2}, "initialD4State": "flipHR90"}})
        with self.assertRaises(ValueError):
            lr.solution_from_drawing(prob, lr.Diagram())


def problem(comps, conns, hints, canvas=()):
    return {"schema": "dyad-layout/problem@1", "settings": {"gridColumns": 20, "gridRows": 20, "options": {}},
            "structure": {"components": comps, "canvasConnectors": list(canvas), "connections": conns},
            "hints": {"components": hints}, "constraints": []}


def ref(c, k):
    return {"type": "component", "componentId": c, "connectorId": k}


TWO_PIN = {"id": "{}", "width": 2, "height": 2, "connectors": [
    {"id": "u", "edge": "left", "position": 0, "direction": "input"},
    {"id": "y", "edge": "right", "position": 0, "direction": "output"}]}


def chain_problem():
    """a.y -> b.u (drawn below) and b.y -> c.u (not drawn): blocks at half-grid (2,2), (6,2), (10,2)."""
    comps = [json.loads(json.dumps(TWO_PIN).replace("{}", n)) for n in "abc"]
    hints = {n: {"initialPosition": {"x": x, "y": 2}} for n, x in zip("abc", (2, 6, 10))}
    return problem(comps, [{"id": "c1", "from": ref("a", "y"), "to": ref("b", "u")},
                           {"id": "c2", "from": ref("b", "y"), "to": ref("c", "u")}], hints)


CHAIN_SVG = svg([("a", 100, 100), ("b", 300, 100), ("c", 500, 100)], ["M 150 100 L 250 100"])


class Unmatched(unittest.TestCase):
    def test_unmatched_connections_get_no_route(self):
        dg = lr.parse_svg(CHAIN_SVG, {"a": 0, "b": 0, "c": 0})
        sol, unmatched = lr.solution_from_drawing(chain_problem(), dg)
        self.assertEqual(unmatched, ["c2"])
        self.assertEqual([r["connectionId"] for r in sol["routedConnections"]], ["c1"])
        self.assertEqual(sol["routedConnections"][0]["waypoints"], [{"x": 3.0, "y": 2.0}, {"x": 5.0, "y": 2.0}])

    def test_partial_scores_are_marked(self):
        rows = [{"diagram": "L.D", "metrics": {"badness": 1, "dl_status": "partial", "dl_crossings": 3, "dl_unmatched": 1},
                 "dyad_layout": {"status": "partial", "connections": 2, "unmatchedConnections": 1}}]
        table = lr.markdown(rows, "badness")
        self.assertIn("dl unmatched", table)
        self.assertIn("| 3* |", table)
        section = "\n".join(lr.scorer_section({"dir": "/w", "release": "v0.1.1", "version": "0.0.1", "pinned": True}, rows))
        self.assertIn("L.D: 1 of 2 connections unmatched", section)

    def test_reroute_error_is_in_the_markdown(self):
        rows = [{"diagram": "L.D", "metrics": {"badness": 1, "dl_status": "complete", "dl_crossings": 0},
                 "dyad_layout": {"status": "complete", "connections": 2, "unmatchedConnections": 0,
                                 "reroutedError": "Error: no legal route for c2\n    at score_layout_json"}}]
        section = "\n".join(lr.scorer_section({"dir": "/w", "release": "v0.1.1", "version": "0.0.1", "pinned": True}, rows))
        self.assertIn("Re-route failed", section)
        self.assertIn("L.D: Error: no legal route for c2", section)
        self.assertNotIn("at score_layout_json", section)

    @unittest.skipUnless(os.environ.get("LAYOUT_REPORT_WASM") and shutil.which("node"),
                         "set LAYOUT_REPORT_WASM to dyad-layout v0.1.1's wasm/pkg to run")
    def test_partial_score_with_the_real_scorer(self):
        wasm = os.environ["LAYOUT_REPORT_WASM"]
        scorer = lr.check_scorer(wasm)
        self.assertEqual((scorer.get("release"), scorer.get("version"), scorer.get("error")), ("v0.1.1", "0.0.1", None))
        out = lr.score_with_wasm(wasm, chain_problem(), lr.parse_svg(CHAIN_SVG, {"a": 0, "b": 0, "c": 0}), {})
        self.assertEqual((out["status"], out["unmatchedConnections"]), ("partial", 1))
        self.assertEqual(out["existing"]["routedConnections"], 1)


JULIA_LOG = textwrap.dedent("""\
    Julia stderr (exit 0): noise
    Precompiling packages...
    ERROR: LoadError: Unsatisfiable requirements detected for package HL20Demo [1f2e3d4c]:
     HL20Demo [1f2e3d4c] log:
     └─restricted to julia version 1.13.2, but julia 1.12.7 is installed
    Stacktrace:
      [1] pkgerror(msg::String)
    ERROR: dyad render failed
    error: compilation failed
    """)


class Diagnostics(unittest.TestCase):
    def test_primary_error_is_the_first(self):
        msg = lr.primary_error(JULIA_LOG)
        self.assertTrue(msg.startswith("ERROR: LoadError: Unsatisfiable requirements"))
        self.assertIn("restricted to julia version 1.13.2", msg)
        self.assertNotIn("Stacktrace", msg)
        self.assertNotIn("compilation failed", msg)

    def test_scorer_checks(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertIn("missing", lr.check_scorer(d)["error"])
            for fn in ("dyad_layout_wasm_bg.wasm", "dyad_layout_wasm.js"):
                with open(os.path.join(d, fn), "w") as f:
                    f.write("not the real thing")
            got = lr.check_scorer(d)
            self.assertIn("does not match a pinned build", got["error"])
            self.assertFalse(got["pinned"])
            self.assertIn("Node", lr.check_scorer(d, allow_unpinned=True, node="no-such-node-binary")["error"])


FAKE_DYAD = """\
import json, sys
args = sys.argv[1:]
if args[0] == "render" and args[1].endswith("Broken"):
    sys.stderr.write({log!r})
    sys.exit(1)
if args[0] == "render":
    with open({svg!r}) as f:
        sys.stdout.write(f.read())
elif args[:2] == ["layout", "extract"] and args[2].endswith("NoProblem"):
    sys.stderr.write("ERROR: extract exploded\\n")
    sys.exit(1)
elif args[:2] == ["layout", "extract"]:
    with open({prob!r}) as f, open(args[args.index("-o") + 1], "w") as g:
        g.write(f.read())
"""


class EndToEnd(unittest.TestCase):
    """main() on a library, with a stand-in for the dyad CLI."""

    def run_main(self, d, *extra):
        def write(path, text):
            with open(path, "w") as f:
                f.write(text)

        def read(path):
            with open(path) as f:
                return f.read()

        lib = os.path.join(d, "Lib")
        os.makedirs(os.path.join(lib, "dyad"))
        write(os.path.join(lib, "Project.toml"), 'name = "Lib"\n')
        write(os.path.join(lib, "dyad", "lib.dyad"),
              "component Chain\n  connect(a.y, b.u)\nend\ncomponent Broken\n  connect(a.y, b.u)\nend\n"
              "component NoProblem\n  connect(a.y, b.u)\nend\n")
        write(os.path.join(d, "chain.svg"), CHAIN_SVG)
        write(os.path.join(d, "prob.json"), json.dumps(chain_problem()))
        fake = os.path.join(d, "dyad")
        write(fake, f"#!{sys.executable}\n" + FAKE_DYAD.format(
            log=JULIA_LOG, svg=os.path.join(d, "chain.svg"), prob=os.path.join(d, "prob.json")))
        os.chmod(fake, 0o755)
        out = os.path.join(d, "out")
        with open(os.devnull, "w") as null:
            old = sys.stdout, sys.stderr
            sys.stdout = sys.stderr = null
            try:
                lr.main(["--dir", lib, "--dyad", fake, "-o", out] + list(extra))
            finally:
                sys.stdout, sys.stderr = old
        rows = {r["diagram"]: r for r in json.loads(read(os.path.join(out, "report.json")))}
        return rows, read(os.path.join(out, "report.md")), out

    def test_scorer_missing_keeps_geometry_and_says_why(self):
        with tempfile.TemporaryDirectory() as d:
            rows, md, _ = self.run_main(d, "--dyad-layout-wasm", os.path.join(d, "no-such-pkg"))
        chain = rows["Lib.Chain"]
        self.assertEqual(chain["metrics"]["wires"], 1)
        self.assertEqual(chain["metrics"]["dl_status"], "unavailable")
        self.assertIn("missing", chain["dyad_layout"]["error"])
        self.assertIn("## dyad-layout scorer", md)
        self.assertIn("Not run: dyad-layout scorer not found", md)

    def test_failed_extract_keeps_geometry_and_the_extract_error(self):
        # a working scorer, but `dyad layout extract` fails for NoProblem: there is nothing to score
        scorer = {"dir": "/w", "release": "v0.1.1", "version": "0.0.1", "pinned": True, "sha256": {}}
        scored = {"status": "complete", "connections": 1, "unmatchedConnections": 0, "unmatchedIds": [],
                  "existing": {"objective": {"crossings": 0, "illegalRoutes": 0, "turns": 0, "spacingPenalty": 0}},
                  "rerouted": {"objective": {"crossings": 2, "illegalRoutes": 1}}}
        with tempfile.TemporaryDirectory() as d, mock.patch.object(lr, "check_scorer", return_value=scorer), \
                mock.patch.object(lr, "score_with_wasm", return_value=scored):
            rows, md, _ = self.run_main(d, "--dyad-layout-wasm", d)
        row = rows["Lib.NoProblem"]
        self.assertNotIn("error", row)
        self.assertEqual((row["metrics"]["wires"], row["metrics"]["blocks"]), (1, 3))
        self.assertIn("ERROR: extract exploded", row["extract_error"])
        self.assertEqual(row["dyad_layout"], {"status": "unavailable", "error": "no extracted problem to score against"})
        self.assertNotIn("dl_rerouted_crossings", row["metrics"])
        self.assertIn("Lib.NoProblem: `dyad layout extract` failed: ERROR: extract exploded", md)
        # the diagram that did extract still gets both scores
        self.assertEqual((rows["Lib.Chain"]["metrics"]["dl_crossings"], rows["Lib.Chain"]["metrics"]["dl_rerouted_crossings"]), (0, 2))

    def test_failed_render_keeps_the_primary_error_and_the_log(self):
        with tempfile.TemporaryDirectory() as d:
            rows, md, out = self.run_main(d)
            broken = rows["Lib.Broken"]
            self.assertIn("restricted to julia version 1.13.2", broken["error"])
            self.assertIn("restricted to julia version 1.13.2", md)
            with open(broken["error_log"]) as f:
                self.assertEqual(f.read(), JULIA_LOG)
            self.assertEqual(os.path.dirname(broken["error_log"]), os.path.join(out, "cache"))


# ---------------------------------------------------------------------------
# Glyphs as Studio draws them. These SVGs have the structure of `dyad render`: a block's <g> holds a
# 1000-unit frame <svg>, its icon in a <g> covering the frame, one <g> per connector glyph, its labels.

TRIANGLE = '<svg width="210" height="210" viewBox="0 0 210 210"><polygon points="5.0,5.0 205.0,105.0 5.0,205.0"/></svg>'


def place(x1, y1, x2, y2, rot=0):
    """The transform `dyad render` gives a placement box (x1..x2, y1..y2) in a 1000-unit frame."""
    return (f'transform="translate({(x1 + x2) / 2 - 500:g} {(y1 + y2) / 2 - 500:g}) rotate({rot}) '
            f'scale({(x2 - x1) / 1000:g} {(y2 - y1) / 1000:g})" transform-origin="center center"')


def gblock(name, box, ports=(), rot=0, label_y=1100):
    """A block in `box`, with connector glyphs at `ports` (boxes in its 1000-unit icon space)."""
    glyphs = "".join(f"<g {place(*p)}>{TRIANGLE}</g>" for p in ports)
    return (f'<g filter="url(#drop-shadow)" {place(*box, rot=rot)}><svg viewBox="0 0 1000 1000">'
            f'<g transform="translate(0 0) scale(1.0) rotate(0)" transform-origin="center center">'
            f'<svg viewBox="0 0 1000 1000"><path d="M4 4h992v992H4z"/></svg></g>{glyphs}'
            f'<text x="500" y="{label_y}" transform="rotate({rot}, 0, 600)" font-size="200">{name}</text></svg></g>')


def gport(box):
    return f"<g {place(*box)}>{TRIANGLE}</g>"


def gsvg(*parts, wires=(), junctions=()):
    body = "".join(parts) + "".join(WIRE.format(d=d) for d in wires)
    body += "".join(f'<circle cx="{x}" cy="{y}" r="2"/>' for x, y in junctions)
    return f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1000 1000">{body}</svg>'


def gm(text, src=None):
    dg = lr.parse_svg(text, src)
    return dg, lr.compute_metrics(dg)


R = lambda b: tuple(round(v, 3) for v in b)


class StudioGeometry(unittest.TestCase):
    def test_icon_keeps_its_aspect_in_a_stretched_box(self):
        # a 200 x 800 box: Studio draws the square icon 200 x 200 in the middle, the pins stay on the box edge
        dg = lr.parse_svg(gsvg(gblock("b", (0, 0, 200, 800), ports=[(-50, 0, 50, 100)])))
        b, = dg.blocks
        self.assertEqual(R(b.frame), (0, 0, 200, 800))
        self.assertEqual(R(b.body), (0, 300, 200, 500))
        g, = dg.glyphs
        self.assertEqual(R(g.frame), (-10, 0, 10, 80))  # the pin's frame, stretched like the box
        self.assertEqual(R(g.pin), (0, 40))
        # the 210-unit triangle fitted into the 20 x 80 frame: a 20 x 20 square, inset by its 5-unit margin
        self.assertEqual(R(g.box), R((-10 + 20 * 5 / 210, 30 + 20 * 5 / 210, 10 - 20 * 5 / 210, 50 - 20 * 5 / 210)))
        self.assertEqual(len(g.shape), 3)

    def test_boundary_port_fills_its_box(self):
        # the glyph <svg> says width="210", but Dyad sizes every frame for 1000 units: 50 x 100 box -> 50 x 50 glyph
        dg = lr.parse_svg(gsvg(gport((100, 200, 150, 300))), {"P": (100, 200, 150, 300)})
        p, = dg.blocks
        self.assertTrue(p.is_port)
        self.assertEqual(p.name, "P")
        self.assertEqual(R(p.frame), (100, 200, 150, 300))
        m = 50 * 5 / 210
        self.assertEqual(R(p.box), R((100 + m, 225 + m, 150 - m, 275 - m)))
        # its name under it: (500, 1100) of the frame grown by 20 units, at Studio's fixed label size
        (_t, lb), = p.labels
        self.assertAlmostEqual((lb[1] + lb[3]) / 2, 180 + 1.1 * 140)
        self.assertAlmostEqual(lb[3] - lb[1], lr.LABEL_HEIGHT)

    def test_labels_are_fixed_size_and_upright(self):
        # a 400 x 100 box: render scales its label 4:1, Studio does not
        dg = lr.parse_svg(gsvg(gblock("wide", (0, 0, 400, 100))))
        (_t, lb), = dg.blocks[0].labels
        self.assertAlmostEqual(lb[3] - lb[1], lr.LABEL_HEIGHT)
        self.assertAlmostEqual(lb[2] - lb[0], lr.label_width("wide"))
        self.assertEqual(((lb[0] + lb[2]) / 2, (lb[1] + lb[3]) / 2), (200, 110))
        # a block turned 180 degrees: the anchor turns with it (above the box), the text stays upright
        dg = lr.parse_svg(gsvg(gblock("flip", (0, 0, 100, 100), rot=180)))
        (_t, lb), = dg.blocks[0].labels
        self.assertEqual(R(((lb[0] + lb[2]) / 2, (lb[1] + lb[3]) / 2)), (50, -10))
        self.assertAlmostEqual(lb[3] - lb[1], lr.LABEL_HEIGHT)

    def test_connector_names_from_the_source(self):
        lib = """
partial component Two
  u1 = RealInput() {^u1}
  y = RealOutput() {"Dyad": {"placement": {"icon": {"x1": 1000, "y1": 450, "x2": 1100, "y2": 550}}}}
metadata {"Dyad": {}, "_links": {"u1": {"Dyad": {"placement": {"icon": {"iconName": "input", "x1": -100, "y1": 200, "x2": 0, "y2": 300},
  "diagram": {"x1": 0, "y1": 0, "x2": 1, "y2": 1}}}}}}
end
component Three
  extends Two()
  u2 = RealInput() {"Dyad": {"placement": {"icon": {"x1": -100, "y1": 700, "x2": 0, "y2": 800}}}}
end
"""
        with tempfile.TemporaryDirectory() as d:
            os.makedirs(os.path.join(d, "dyad"))
            with open(os.path.join(d, "dyad", "t.dyad"), "w") as f:
                f.write(lib)
            idx = lr.connector_index([os.path.join(d, "dyad")])
        self.assertEqual(sorted(idx["Three"]), [("u1", (-100, 200, 0, 300)), ("u2", (-100, 700, 0, 800)), ("y", (1000, 450, 1100, 550))])
        dg = lr.parse_svg(gsvg(gblock("t", (0, 0, 100, 100), ports=[(-100, 200, 0, 300), (-100, 450, 0, 550)])),
                          {"t": (0, 0, 100, 100)}, {"t": idx["Three"]})
        self.assertEqual([g.name for g in dg.glyphs], ["t.u1", "t.#2"])

    def test_instance_boxes_follow_links(self):
        block = """
  a = Lib.Gain(k = 1) {^a}
  b = Lib.Gain() {"Dyad": {"placement": {"diagram": {"x1": 0, "y1": 0, "x2": 100, "y2": 100}}}}
relations
metadata {"Dyad": {}, "_links": {"a": {"Dyad": {"placement": {"icon": {"x1": 1, "y1": 1, "x2": 2, "y2": 2},
  "diagram": {"x1": 200, "y1": 0, "x2": 300, "y2": 100}}}}}}
"""
        self.assertEqual(lr.instance_boxes(block), {"a": (200, 0, 300, 100), "b": (0, 0, 100, 100)})


class GlyphChecks(unittest.TestCase):
    def test_glyph_overlap(self):
        # three ports in a column, 100 apart: the first two touch, the third is 50 units clear
        dg, (m, d) = gm(gsvg(gport((0, 0, 100, 100)), gport((0, 100, 100, 200)), gport((0, 250, 100, 350))))
        self.assertEqual((m["glyph_overlap"], m["glyph_overlap_unwired"]), (1, 0))
        # triangles whose boxes only touch at a corner do not touch
        _dg, (m, _d) = gm(gsvg(gport((0, 0, 100, 100)), gport((100, 100, 200, 200))))
        self.assertEqual(m["glyph_overlap"], 0)
        # a port glyph on another block's icon
        _dg, (m, d) = gm(gsvg(gblock("b", (0, 0, 100, 100)), gport((60, 20, 160, 120))))
        self.assertEqual((m["glyph_overlap"], d["glyph_overlap"]), (1, ["port#1 on b"]))

    def test_unwired_pins_piled_on_one_block_are_reported_apart(self):
        stacked = [(950, y, 1050, y + 50) for y in (0, 50)]
        _dg, (m, _d) = gm(gsvg(gblock("b", (0, 0, 1000, 1000), ports=stacked)))
        self.assertEqual((m["glyph_overlap"], m["glyph_overlap_unwired"]), (0, 1))
        # once one is wired, it is this diagram's layout
        _dg, (m, _d) = gm(gsvg(gblock("b", (0, 0, 1000, 1000), ports=stacked), wires=["M 1000 25 L 1200 25"]))
        self.assertEqual((m["glyph_overlap"], m["glyph_overlap_unwired"]), (1, 0))

    def test_glyph_detached_and_overhang(self):
        # 400 x 100 box: the icon is the middle 100 x 100; a pin on the box's left edge floats 150 away
        _dg, (m, d) = gm(gsvg(gblock("b", (0, 0, 400, 100), ports=[(-50, 450, 50, 550), (450, -50, 550, 50)])))
        self.assertEqual(m["glyph_detached"], 1)
        self.assertEqual(d["glyph_detached"], ["b.#1 (145 from b)"])  # its 10 x 10 glyph is centred on x = 0
        self.assertEqual(m["glyph_overhang"], 0)  # the top pin straddles the top side
        # on a 100-unit block: a pin past the corner of its side, a standard pin standing just off the side
        # (BlockComponents' `x1 = -100, x2 = 0`: 10 units out, fine), and a 40-unit glyph standing off it
        _dg, (m, d) = gm(gsvg(gblock("b", (0, 0, 100, 100), ports=[(-50, 1000, 50, 1100), (-100, 300, 0, 400),
                                                                  (-400, 600, 0, 1000)])))
        self.assertEqual((m["glyph_detached"], m["glyph_overhang"]), (0, 2))
        self.assertIn("past the end of the left side", d["glyph_overhang"][0])
        self.assertIn("outside the left side", d["glyph_overhang"][1])

    def test_label_covered(self):
        # a port right under another port's name; a block's own bottom pin over its own label does not count
        _dg, (m, d) = gm(gsvg(gport((0, 0, 100, 100)), gport((0, 110, 100, 210)),
                              gblock("b", (500, 0, 600, 100), ports=[(450, 1000, 550, 1100)])),
                         {"A": (0, 0, 100, 100), "B": (0, 110, 100, 210), "b": (500, 0, 600, 100)})
        self.assertEqual((m["label_covered"], d["label_covered"]), (1, ["A under B"]))

    def test_wire_thru_glyph(self):
        port = gport((200, 0, 300, 100))
        # through the middle of a 95-unit triangle; ending at it; grazing its tip
        for wire, want in (("M 0 50 L 400 50", 1), ("M 0 50 L 250 50", 0), ("M 290 -50 L 290 150", 0)):
            _dg, (m, _d) = gm(gsvg(port, wires=[wire]))
            self.assertEqual((m["wire_thru_glyph"], m["wire_through_port"]), (want, want), wire)
        # a wire of the glyph's own net (the two wires share an end) is not counted
        _dg, (m, _d) = gm(gsvg(port, wires=["M 250 50 L 250 200 L 600 200", "M 600 200 L 600 50 L 0 50"]))
        self.assertEqual(m["wire_thru_glyph"], 0)
        # a block's 10-unit pin is too small to test: a wire has to run over it to reach the pin
        _dg, (m, _d) = gm(gsvg(gblock("b", (500, 0, 600, 100), ports=[(-100, 450, 0, 550)]), wires=["M 495 -50 L 495 150"]))
        self.assertEqual(m["wire_thru_glyph"], 0)

    def test_junction_on_glyph(self):
        port = gport((200, 0, 300, 100))
        for jp, want in (((260, 50), 1), ((300, 50), 1), ((320, 50), 0)):
            _dg, (m, _d) = gm(gsvg(port, junctions=[jp]))
            self.assertEqual(m["junction_on_glyph"], want, jp)

    def test_near_diagonal(self):
        _dg, (m, d) = gm(gsvg(wires=["M 0 561.42 L 300 561.4 L 300 900", "M 0 0 L 300 0.0000001", "M 0 1000 L 300 1001"]))
        self.assertEqual(m["near_diagonal"], 1)
        self.assertEqual(m["diagonal_segments"], 1)


# ---------------------------------------------------------------------------
# Regression fixtures: `dyad render` output of HL20Demo diagrams at 99ffbc0 (draft PR #51), gzipped,
# with the counts the glyph checks must give. Every listed defect was checked against Dyad Studio's own
# drawing (dyad-ui-shot); the clean ones look clean there. studio.json holds the geometry Studio drew
# for them, read from its DOM, which the model must reproduce.

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")


def fixture(name):
    import gzip
    with gzip.open(os.path.join(FIXTURES, name + ".svg.gz"), "rt", encoding="utf-8") as f:
        return f.read()


class Fixtures(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        with open(os.path.join(FIXTURES, "expected.json")) as f:
            cls.expected = json.load(f)
        with open(os.path.join(FIXTURES, "studio.json")) as f:
            cls.studio = json.load(f)

    def test_counts(self):
        for name, exp in self.expected.items():
            dg = lr.parse_svg(fixture(name), {k: tuple(v) for k, v in exp["src_boxes"].items()})
            m, _d = lr.compute_metrics(dg)
            self.assertEqual({k: m[k] for k in exp["counts"]}, exp["counts"], name)

    def test_matches_studio(self):
        for name, st in self.studio.items():
            src = {k: tuple(v) for k, v in self.expected[name]["src_boxes"].items()}
            dg = lr.parse_svg(fixture(name), src)
            close = lambda a, b, tol=1.0: max(abs(u - v) for u, v in zip(a, b)) <= tol
            bodies = {b.name: b.body for b in dg.blocks if not b.is_port}
            for nm, ink in st["bodies"].items():
                self.assertTrue(close(bodies[nm], ink), (name, nm, bodies[nm], ink))
            glyphs = [g.box for g in dg.glyphs]
            for ink in st["glyphs"]:
                self.assertTrue(any(close(g, ink) for g in glyphs), (name, ink))
            self.assertEqual(len(glyphs), len(st["glyphs"]), name)
            labels = [(t, bb) for b in dg.blocks for t, bb in b.labels]
            for text, box in st["labels"]:
                centre = lambda bb: ((bb[0] + bb[2]) / 2, (bb[1] + bb[3]) / 2)
                self.assertTrue(any(t == text and close(centre(bb), centre(box)) for t, bb in labels), (name, text, box))


if __name__ == "__main__":
    unittest.main()
