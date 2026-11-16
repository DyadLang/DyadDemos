"""Unit tests for layout_report's geometry: python3 -m unittest tools/layout-report/test_layout_report.py"""
import json
import os
import shutil
import subprocess
import sys
import tempfile
import textwrap
import unittest

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
              "component Chain\n  connect(a.y, b.u)\nend\ncomponent Broken\n  connect(a.y, b.u)\nend\n")
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

    def test_failed_render_keeps_the_primary_error_and_the_log(self):
        with tempfile.TemporaryDirectory() as d:
            rows, md, out = self.run_main(d)
            broken = rows["Lib.Broken"]
            self.assertIn("restricted to julia version 1.13.2", broken["error"])
            self.assertIn("restricted to julia version 1.13.2", md)
            with open(broken["error_log"]) as f:
                self.assertEqual(f.read(), JULIA_LOG)
            self.assertEqual(os.path.dirname(broken["error_log"]), os.path.join(out, "cache"))


if __name__ == "__main__":
    unittest.main()
