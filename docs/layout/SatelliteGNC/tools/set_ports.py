#!/usr/bin/env python3
"""Give every connector of the SatelliteGNC child components an icon placement.

Each component has a canonical square instance size S (parent-diagram units).
Port offsets are given in parent units from the top of the box, so with the
box on the 50-unit layout grid every port lands on a grid point.  The same
boxes are written as the connectors' own `diagram` placements so the component's
diagram shows the ports where its icon does.

usage: set_ports.py LIBDIR [COMPONENT ...]
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dyadmeta as dm  # noqa: E402

PORT = 30      # rendered connector size, parent units
LABEL = 36     # rendered instance-label height, parent units

SPECS = {
    'TrapezoidalProfile': dict(
        file='dyad/trajectory_profile.dyad', S=200,
        icon='dyad://SatelliteGNC/TrapezoidalProfile.svg',
        right=[('angle_ref', 50), ('rate_ref', 100), ('accel_ref', 150)]),
    'SatelliteBody': dict(
        file='dyad/satellite_body.dyad', S=400,
        icon='dyad://SatelliteGNC/SatelliteBody.svg',
        left=[('tau_x', 150), ('tau_y', 200), ('tau_z', 250)],
        right=[('phi_out', 50), ('theta_out', 100), ('psi_out', 150),
               ('wx_out', 250), ('wy_out', 300), ('wz_out', 350)]),
    'LuenbergerObserver': dict(
        file='dyad/observer.dyad', S=400,
        icon='dyad://SatelliteGNC/LuenbergerObserver.svg',
        left=[('phi_meas', 50), ('theta_meas', 100), ('psi_meas', 150),
              ('tau_x', 250), ('tau_y', 300), ('tau_z', 350)],
        right=[('phi_hat', 50), ('theta_hat', 100), ('psi_hat', 150),
               ('wx_hat', 250), ('wy_hat', 300), ('wz_hat', 350)]),
    'AttitudeController': dict(
        file='dyad/attitude_controller.dyad', S=800,
        icon='dyad://SatelliteGNC/AttitudeController.svg',
        # measurements on top (feedback wires come over the top of the diagram),
        # then the references grouped per axis (angle, rate, accel feed-forward)
        # so each TrapezoidalProfile block's three outputs stay together
        left=[('phi_meas', 50), ('theta_meas', 100), ('psi_meas', 150),
              ('wx_meas', 200), ('wy_meas', 250), ('wz_meas', 300),
              ('phi_ref', 350), ('wx_ref', 400), ('ax_ff', 450),
              ('theta_ref', 500), ('wy_ref', 550), ('ay_ff', 600),
              ('psi_ref', 650), ('wz_ref', 700), ('az_ff', 750)],
        right=[('tau_x', 350), ('tau_y', 400), ('tau_z', 450)]),
    'ThrusterAllocator': dict(
        file='dyad/thruster_allocator.dyad', S=500,
        icon='dyad://SatelliteGNC/ThrusterAllocator.svg',
        left=[('Fx_cmd', 100), ('Fy_cmd', 150), ('Fz_cmd', 200),
              ('tau_x_cmd', 300), ('tau_y_cmd', 350), ('tau_z_cmd', 400)],
        right=[('cmd1', 50), ('cmd2', 100), ('cmd3', 150), ('cmd4', 200),
               ('cmd5', 300), ('cmd6', 350), ('cmd7', 400), ('cmd8', 450)]),
    'ReactionJet': dict(
        file='dyad/reaction_jet.dyad', S=400,
        icon='dyad://SatelliteGNC/ReactionJet.svg',
        left=[('cmd', 200)],
        right=[('fx_out', 50), ('fy_out', 100), ('fz_out', 150),
               ('tx_out', 250), ('ty_out', 300), ('tz_out', 350)]),
    'SatelliteBody6DOF': dict(
        file='dyad/satellite_body_6dof.dyad', S=700,
        icon='dyad://SatelliteGNC/SatelliteBody6DOF.svg',
        left=[('tau_x', 150), ('tau_y', 200), ('tau_z', 250),
              ('fx', 450), ('fy', 500), ('fz', 550)],
        right=[('phi_out', 50), ('theta_out', 100), ('psi_out', 150),
               ('wx_out', 200), ('wy_out', 250), ('wz_out', 300),
               ('x_out', 400), ('y_out', 450), ('z_out', 500),
               ('vx_out', 550), ('vy_out', 600), ('vz_out', 650)]),
}


def r(v):
    v = round(v, 3)
    return int(v) if v == int(v) else v


def box(edge, off, S):
    k = 1000 / S
    h = PORT * k / 2
    c = off * k
    x = 0 if edge == 'left' else 1000
    return {'iconName': 'default', 'x1': r(x - h), 'y1': r(c - h), 'x2': r(x + h), 'y2': r(c + h), 'rot': 0}


def apply(lib, name, spec):
    path = os.path.join(lib, spec['file'])
    S = spec['S']
    ports = [('left', n, o) for n, o in spec.get('left', [])] + [('right', n, o) for n, o in spec.get('right', [])]
    offs = {}
    for e, n, o in ports:
        assert o % 50 == 0 and 0 < o < S, (name, n, o)
        assert (e, o) not in offs, (name, n, o)
        offs[(e, o)] = n
    src = open(path).read()
    src = dm.ensure_tags(src, name, [n for _, n, _ in ports])
    open(path, 'w').write(src)
    _, meta, _, _ = dm.load(path, name)
    d = meta.setdefault('Dyad', {})
    d['icons'] = {'default': spec['icon']}
    fs = LABEL * 1000 / S
    d['labels'] = [{'label': '$(instance)', 'x': 500, 'y': r(1000 + 0.7 * fs), 'layer': 'icon',
                    'attrs': {'font-size': str(r(fs))}}]
    for e, n, o in ports:
        lk = dm.link(meta, n)
        b = box(e, o, S)
        lk['placement'] = {'icon': b, 'diagram': dict(b)}
        lk.setdefault('tags', [])
    dm.save(path, name, meta)
    print(f'{name}: {len(ports)} ports, S={S}')


if __name__ == '__main__':
    lib = sys.argv[1]
    names = sys.argv[2:] or list(SPECS)
    for n in names:
        apply(lib, n, SPECS[n])
