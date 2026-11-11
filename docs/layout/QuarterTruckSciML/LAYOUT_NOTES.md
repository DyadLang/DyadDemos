# QuarterTruckSciML diagram re-layout

Toolchain: Dyad CLI 3.5.0 (`dyad-linux-x64`, release v3.5.0, SHA256 checked),
`JULIA_EXECUTABLE="julia +dyad-3.5.0"`, and the scout's `layout-tools`.
`relayout.sh` is run from the demo root. `PIN(id,x,y)` below is shorthand for

    add:{"id":"pin:ID","kind":{"kind":"pin","componentId":"ID","at":{"x":X,"y":Y}},"strength":{"tier":"required","weight":1}}

`CHAIN(a b c ...)` is one `order` constraint per neighbouring pair (a left of b, ...), each at strength strong/1:

    add:{"id":"ord:a:b","kind":{"kind":"order","a":"a","b":"b","dir":"left"},"strength":{"tier":"strong","weight":1}}

Solver coordinates are in half-squares (1 = 50 diagram units). `before.png` is
`main` at f8723d5 and `after.png` is this branch.

## Child component fixes (done first, bottom-up)

- **`ConfigurableTireSpringDamper`, `ViscoelasticSpringDamper`, `CoulombFriction`**
  (`truck_model.dyad`) had no metadata at all. Every wire met at the middle of a
  placeholder icon. Changes:
  - Icons: `TranslationalComponents/SpringDamper.svg` for the two spring-dampers, and
    `TranslationalComponents/SignForce.svg` for Coulomb friction (its tanh curve is
    exactly `F_c·tanh(v/v0)`).
  - Flanges get `{^flange_a}`/`{^flange_b}` tags plus icon placements matching
    TranslationalComponents' `PartialTwoFlanges`. The tags matter: `_links` entries are
    looked up by tag.
- **`Mux3` / `Demux3`**: the connectors sat at y=240/500/770, but `Mux_3.svg`/`Demux_3.svg`
  drew their lines at 130/500/870. Changes:
  - The SVG lines move to 250/500/750, keeping the same 45° geometry.
  - The connectors get matching `icon` and `diagram` placements at 250/500/750.
  - The instance boxes become 200×200, so the ports end up 50 apart on the grid.
- **`TireWithExternalResidual`, `PureExternalForce`, `SpringDamperWithExternalResidual`**:
  - Top ports now have icon-layer placements: 100-wide boxes centred on the top edge
    at x=250 and x=750.
  - Order: Tire puts the force input left and `s_rel_out` right. PureExternalForce and
    SpringDamperWithExternalResidual put the measured output left and the force input right.
  - This order is what lets the FullNN feedback loops nest (see below). Each of these
    components is used only in `QuarterTruckFullNN`.
- **`HalfSineBump`, `ISO8608Road`, `DenseISO8608Road`** had no icon, and their `y`
  output sat in the top-left corner. They get BlockComponents' `SO` output placement
  (right edge, centred) and icons: `BlockComponents/Pulse.svg` for the bump,
  `BlockComponents/SineVariableFrequencyAndAmplitude.svg` for the ISO 8608 sums of sines.

## Per-diagram notes

| Diagram | Before | Method | Result |
|---|---|---|---|
| `QuarterTruckConfigurable` | C: custom elements had no ports, so wires met at block centres; tiny blocks spread wide | solver | A: 0 crossings, 4 turns |
| `ScaledNeuralNetworkBlock` | B-: `norm_tire` and `seat_prod` vertically flipped, so their names rendered mirrored; mux/demux ports didn't match their icons | solver + pins | A-: 1 crossing (seat product inputs, topologically forced without a flip) |
| `QuarterTruckFullNN` | C: about 8 crossings, wires into port-less blocks | hand (solver rejected) | A-: 2 crossings |
| `TestQuarterTruckFullNNSin` | A | unchanged | A |
| `TestQuarterTruckFullNNISOA` | D: unplaced, both blocks stacked | hand | A |
| `TestQuarterTruckConfigurableFullSin`, `TestQuarterTruckLinearISOA`, `TestQuarterTruckNonlinearISOA` | can't be rendered | not changed | see below |

### QuarterTruckConfigurable

    relayout.sh QuarterTruckConfigurable OUT lock-orientation opt:routingRefinement=2 \
      CHAIN(road tire_to_road tire tire_to_body body body_to_seat seat seat_to_driver driver) \
      'add:{"id":"al:main","kind":{"kind":"align","componentIds":["road","tire_to_road","tire","tire_to_body","body","body_to_seat","seat","seat_to_driver","driver"],"axis":"horizontal"}}' \
      'add:{"id":"o:f1","kind":{"kind":"order","a":"tire","b":"friction_tb","dir":"left"}}' \
      'add:{"id":"o:f2","kind":{"kind":"order","a":"friction_tb","b":"body","dir":"left"}}' \
      'add:{"id":"o:f3","kind":{"kind":"order","a":"friction_tb","b":"tire_to_body","dir":"above"}}'

Acausal flanges carry no direction, so without the chain the solver ran the
truck right-to-left and every wire looped back on itself.

### ScaledNeuralNetworkBlock

    relayout.sh ScaledNeuralNetworkBlock OUT lock-orientation unpin-ports port-edges \
      PIN(in_tire,0,7.4) PIN(norm_tire,12,8) PIN(s_rel0_src,7,10)

The original boxes had `y1 > y2` on `norm_tire` and `seat_prod` (a vertical flip),
which mirrored their names. `lock-orientation` restores identity. The pins keep
`s_rel0_src` below the `in_tire` wire so it feeds `norm_tire.u2` without
looping over it. After `apply`, the six boundary-connector diagram boxes were
shrunk by hand from 80×80 to 40×40, keeping their centres. The renderer draws
the port glyph away from the box centre, where the wire ends, by an amount that
grows with the box size.

### QuarterTruckFullNN

Solver attempts, all rejected:

- `lock-orientation unpin-ports port-edges opt:routingRefinement=2` plus the chain/align
  hints above put `scaled_nn` below the truck: 8 crossings, with every NN wire wrapping around.
- Adding vertical `align` of `scaled_nn`/`friction_tb`/`tire_to_body`, `order above`,
  and pins gave 9–12 crossings. The soft orders were traded away and the pins only
  held relative to the moving main row.

Hand layout (100×100 blocks, 200 pitch, main row centred at y=500):

- Main row x-centres: road 100, tire_to_road 300, tire 500, friction_tb 700, body 900,
  body_to_seat 1100, seat 1300, seat_to_driver 1500, driver 1700.
- `tire_to_body` (700,700), parallel to `friction_tb`. `road_fixed` (100,700).
  `s_rel` port at (−50,500).
- `scaled_nn` at 900..1100 × 50..250, so its inputs/outputs sit at y=100/150/200.
- NN loops:
  - Tire: up at x=325 to y=100. The return goes out at x=1200, over the top at y=0, and down at x=275.
  - Friction: up at x=675 to y=150. The return goes down at x=1150, along y=400, and into x=725.
  - Seat: forward up at x=1475 to y=350, then left to x=850 and up to y=200. The return runs along y=200 to x=1525.
- `tire_to_body` branch: `M [(600,500),(600,700)]` in, `M [(800,700),(800,500)]` out.

The friction loop wraps the lower half of the NN block, so both seat wires
have to cross it once (2 crossings). Putting the NN below the truck, or sending
the friction loop over the top, just moves the same crossings to the tire loop.

### TestQuarterTruckFullNNISOA

Tags were added to both instances and the connect. `iso_road` is at 300..400 × 450..550
and `model` at 500..600 × 450..550, a straight wire, matching `TestQuarterTruckFullNNSin`.

### Not laid out

`TestQuarterTruckConfigurableFullSin`, `TestQuarterTruckLinearISOA` and
`TestQuarterTruckNonlinearISOA` connect to the nested connector
`model.road.s_ref`. Dyad 3.5.0 refuses both `layout extract` and `render` for
these (`invalid-reference: Connector reference model.road.s_ref isn't supported`).
Fixing that means exposing an `s_rel` input on `QuarterTruckConfigurable`, as
`QuarterTruckFullNN` does. That is a model change, so it's left for a separate PR.
`QuarterTruckFullNN` itself is a top-level model, which AGENTS.md exempts from
needing an icon, so it still shows the placeholder icon in its test harnesses.
