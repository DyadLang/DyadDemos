"""Unit tests for layout_report's geometry: python3 -m unittest tools/layout-report/test_layout_report.py"""
import os
import sys
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


if __name__ == "__main__":
    unittest.main()
