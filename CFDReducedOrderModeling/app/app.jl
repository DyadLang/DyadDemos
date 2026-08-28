#=
CFD Reduced-Order Modeling Dashboard
=====================================
Lightweight app: HTTP.jl server + Plotly.js frontend.

Loads pre-computed CFD data from CSV. ROMs are Dyad components compiled
and simulated via ModelingToolkit.

Three data-driven ROM methods:
  - POD/DMDc:            SVD of snapshots → DMDc dynamics → k-means zones
  - SVD Thermal Network: SVD → k-means zones → calibrated tridiagonal network
  - Neural ODE Network:  Latent Neural ODE → k-means zones → calibrated network

Launch:  julia --project=.. app.jl
Open:    http://localhost:9000
=#

using HTTP, JSON, LinearAlgebra, Statistics
using CSV, DataFrames
using CFDReducedOrderModeling
using ModelingToolkit
using DyadInterface: symbolic_container

# ════════════════════════════════════════════════════════════════
#  Load CFD data from CSV
# ════════════════════════════════════════════════════════════════

const DATA_DIR = joinpath(@__DIR__, "..", "data")
const T_REF    = 300.0
const N_NODES  = 20

println("Loading data...")

function load_spatial(path)
    df = CSV.read(path, DataFrame)
    cols = sort(
        [c for c in names(df) if match(r"^T_\d+$", c) !== nothing],
        by = c -> parse(Int, match(r"(\d+)$", c).captures[1]))
    t = Vector{Float64}(df.time)
    Q = Vector{Float64}(df.Q_in)
    T = Matrix{Float64}(df[:, cols])
    return (; t, Q, T)
end

const TRAIN = load_spatial(joinpath(DATA_DIR, "cfd_training_data.csv"))
const VAL   = load_spatial(joinpath(DATA_DIR, "cfd_validation_data.csv"))
println("  Training:   $(length(TRAIN.t)) steps")
println("  Validation: $(length(VAL.t)) steps")

# SVD energy from training snapshots
const TRAIN_THETA = TRAIN.T .- T_REF
const SVD_F       = svd(TRAIN_THETA')
const SVD_ENERGY  = cumsum(SVD_F.S .^ 2) ./ sum(SVD_F.S .^ 2)

energy_lines = ["Snapshot SVD energy (training data):"]
for k in 1:min(6, length(SVD_ENERGY))
    push!(energy_lines, "  k=$k: $(round(100*SVD_ENERGY[k], digits=3))%")
end
const ENERGY_TEXT = join(energy_lines, "\n")
println("Data loaded ✓")

# ════════════════════════════════════════════════════════════════
#  Compile Dyad ROM models
# ════════════════════════════════════════════════════════════════

println("\nCompiling Dyad ROMs...")

@named SVD_SYS  = TestSVDThermalNetworkROM()
const SVD_C     = mtkcompile(SVD_SYS)
println("  ✓ SVD Thermal Network ROM")

@named NODE_SYS = TestNeuralODEThermalNetworkROM()
const NODE_C    = mtkcompile(NODE_SYS)
println("  ✓ Neural ODE Thermal Network ROM")

@named POD_SYS  = TestPODDMDcROM()
const POD_C     = mtkcompile(POD_SYS)
println("  ✓ POD/DMDc ROM")

println("Dyad ROMs compiled ✓")

# Zone membership for each ROM (matches Dyad component docstrings)
const ZONE_MEMBERS = Dict(
    "SVD Network"        => [collect(1:5), collect(6:10), collect(11:14), collect(15:20)],
    "Neural ODE Network" => [collect(1:2), collect(3:6), collect(7:12), collect(13:20)],
    "POD/DMD"            => [collect(1:4), collect(5:11), collect(12:20)],
)

# ════════════════════════════════════════════════════════════════
#  Helpers
# ════════════════════════════════════════════════════════════════

function zone_averages_equal(T_mat, n_zones)
    N = size(T_mat, 2);  npz = N ÷ n_zones
    [vec(mean(T_mat[:, (npz*(z-1)+1):(npz*z)], dims=2)) for z in 1:n_zones]
end

function zone_averages_members(T_mat, members)
    [vec(mean(T_mat[:, m], dims=2)) for m in members]
end

# ════════════════════════════════════════════════════════════════
#  API: /api/training  — return pre-loaded training data
# ════════════════════════════════════════════════════════════════

function handle_training(req)
    body = JSON.parse(String(req.body))
    n_zones = body["n_zones"]
    zt = zone_averages_equal(TRAIN.T, n_zones)

    resp = Dict(
        "t"           => TRAIN.t,
        "u"           => TRAIN.Q,
        "zone_temps"  => zt,
        "energy_text" => ENERGY_TEXT,
    )
    HTTP.Response(200, ["Content-Type" => "application/json"], JSON.json(resp))
end

# ════════════════════════════════════════════════════════════════
#  API: /api/validate  — simulate Dyad ROM and compare to CFD
# ════════════════════════════════════════════════════════════════

function handle_validate(req)
    body = JSON.parse(String(req.body))
    rom_type = body["rom_type"]

    members = ZONE_MEMBERS[rom_type]
    theta_val = VAL.T .- T_REF
    cfd_zones = zone_averages_members(theta_val, members)
    n_zones = length(members)

    local rom_zones, method_label

    if rom_type == "SVD Network"
        prob = ODEProblem(SVD_C, [], (0.0, VAL.t[end]))
        sol = solve(prob; saveat=VAL.t)
        rom_zones = [sol[SVD_C.rom.theta1], sol[SVD_C.rom.theta2],
                     sol[SVD_C.rom.theta3], sol[SVD_C.rom.theta4]]
        zs = [length(m) for m in members]
        method_label = "SVD Thermal Network (4 zones $zs) — Dyad"

    elseif rom_type == "Neural ODE Network"
        prob = ODEProblem(NODE_C, [], (0.0, VAL.t[end]))
        sol = solve(prob; saveat=VAL.t)
        rom_zones = [sol[NODE_C.rom.theta1], sol[NODE_C.rom.theta2],
                     sol[NODE_C.rom.theta3], sol[NODE_C.rom.theta4]]
        zs = [length(m) for m in members]
        method_label = "Neural ODE Network (4 zones $zs) — Dyad"

    elseif rom_type == "POD/DMD"
        prob = ODEProblem(POD_C, [], (0.0, VAL.t[end]))
        sol = solve(prob; saveat=VAL.t)
        rom_zones = [sol[POD_C.rom.theta1], sol[POD_C.rom.theta2],
                     sol[POD_C.rom.theta3]]
        zs = [length(m) for m in members]
        method_label = "POD/DMDc (k=2, 3 zones $zs) — Dyad"

    else
        return HTTP.Response(200, JSON.json(Dict("error" => "Unknown ROM type: $rom_type")))
    end

    # Convert to absolute temperature for display
    T_rom = [r .+ T_REF for r in rom_zones]
    T_cfd = [c .+ T_REF for c in cfd_zones]

    # Metrics (on deviations — same scale)
    nz = length(rom_zones)
    rms_vals = [sqrt(mean((rom_zones[z] .- cfd_zones[z]).^2)) for z in 1:nz]
    max_vals = [maximum(abs.(rom_zones[z] .- cfd_zones[z])) for z in 1:nz]
    overall  = sqrt(mean(rms_vals.^2))

    error_lines = [method_label, "Validation on unseen ramp input", ""]
    for z in 1:nz
        push!(error_lines, "  Zone $z:  RMS=$(round(rms_vals[z],digits=4)) K  Max=$(round(max_vals[z],digits=4)) K")
    end
    push!(error_lines, "", "  Overall RMS: $(round(overall, digits=4)) K")

    # Relative error [%] = (ROM - CFD) / CFD * 100
    err_zones = [100.0 .* (T_rom[z] .- T_cfd[z]) ./ T_cfd[z] for z in 1:nz]

    resp = Dict(
        "t"           => collect(VAL.t),
        "cfd_zones"   => T_cfd,
        "rom_zones"   => T_rom,
        "err_zones"   => err_zones,
        "error_text"  => join(error_lines, "\n"),
        "method"      => method_label,
        "overall_rms" => round(overall, digits=4),
    )
    HTTP.Response(200, ["Content-Type" => "application/json"], JSON.json(resp))
end

# ════════════════════════════════════════════════════════════════
#  HTML page (self-contained, Plotly.js from CDN)
# ════════════════════════════════════════════════════════════════

const INDEX_HTML = """
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>CFD ROM Dashboard</title>
<script src="https://cdn.plot.ly/plotly-2.27.0.min.js"></script>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
         background: #f0f2f5; color: #333; }
  .header { background: #1a237e; color: white; padding: 14px 24px; }
  .header h1 { font-size: 20px; font-weight: 500; }
  .header p { color: rgba(255,255,255,0.7); font-size: 13px; margin-top: 2px; }
  .main { display: grid; grid-template-columns: 1fr 320px; gap: 12px;
           padding: 12px; max-width: 1400px; margin: 0 auto; }
  .card { background: white; border-radius: 8px; padding: 16px;
          box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
  .card h3 { font-size: 13px; color: #1a237e; border-bottom: 2px solid #1a237e;
             padding-bottom: 4px; margin-bottom: 10px; }
  label { display: block; font-size: 12px; color: #555; margin: 6px 0 2px; }
  select { width: 100%; padding: 6px 8px; border: 1px solid #ccc;
           border-radius: 4px; font-size: 13px; }
  .btn { display: block; width: 100%; padding: 10px; border: none; border-radius: 6px;
         color: white; font-size: 14px; cursor: pointer; margin-top: 10px; }
  .btn-purple { background: #6a1b9a; }
  .btn-purple:hover { background: #7b1fa2; }
  .btn:disabled { opacity: 0.5; cursor: wait; }
  .status { background: #f5f5f5; border-top: 1px solid #ddd; padding: 8px 20px;
            font-size: 13px; margin-top: 12px; text-align: center; }
  pre.metrics { font-size: 11px; background: #f5f5f5; padding: 8px; border-radius: 4px;
                white-space: pre-wrap; margin-top: 8px; color: #333; }
  .bottom { display: grid; grid-template-columns: 1.4fr 1fr; gap: 12px;
            padding: 0 12px 12px; max-width: 1400px; margin: 0 auto; }
  .plot-box { min-height: 300px; }
  .data-info { font-size: 11px; color: #666; background: #f9f9f9; padding: 8px;
               border-radius: 4px; margin-top: 8px; }
  .diagram-row { padding: 12px 12px 0; max-width: 1400px; margin: 0 auto; }
  .diagram-row .card { text-align: center; }
  .diagram-row svg { max-width: 100%; height: auto; }
</style>
</head>
<body>

<div class="header">
  <h1>CFD Reduced-Order Modeling Dashboard</h1>
  <p>Data-driven ROMs compiled in Dyad — POD/DMDc · SVD Thermal Network · Neural ODE Network</p>
</div>

<!-- DIAGRAM ROW -->
<div class="diagram-row">
  <div class="card">
    <h3>Oil Passage Wall — 20-Node 1D Thermal Model</h3>
    <svg viewBox="0 0 960 220" xmlns="http://www.w3.org/2000/svg" style="display:inline-block; max-width:920px;">
      <defs>
        <marker id="ah" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
          <path d="M0,0 L8,3 L0,6 Z" fill="#c62828"/>
        </marker>
        <marker id="ab" markerWidth="8" markerHeight="6" refX="8" refY="3" orient="auto">
          <path d="M0,0 L8,3 L0,6 Z" fill="#1565c0"/>
        </marker>
        <linearGradient id="wallGrad" x1="0" y1="0" x2="1" y2="0">
          <stop offset="0%" stop-color="#d32f2f" stop-opacity="0.12"/>
          <stop offset="100%" stop-color="#1565c0" stop-opacity="0.10"/>
        </linearGradient>
      </defs>

      <!-- Oil side -->
      <rect x="20" y="50" width="90" height="130" rx="6" fill="#fff3e0" stroke="#e65100" stroke-width="1.5"/>
      <text x="65" y="42" text-anchor="middle" font-size="11" font-weight="600" fill="#e65100">HOT OIL</text>
      <text x="65" y="108" text-anchor="middle" font-size="20">🛢️</text>
      <text x="65" y="135" text-anchor="middle" font-size="9" fill="#bf360c">Q_in →</text>

      <!-- Q_in arrow -->
      <line x1="112" y1="115" x2="148" y2="115" stroke="#c62828" stroke-width="2.5" marker-end="url(#ah)"/>
      <text x="130" y="106" text-anchor="middle" font-size="9" font-weight="600" fill="#c62828">Q_in</text>

      <!-- Cast iron wall -->
      <rect x="155" y="50" width="640" height="130" rx="4" fill="url(#wallGrad)" stroke="#616161" stroke-width="1.5"/>
      <text x="475" y="42" text-anchor="middle" font-size="11" font-weight="600" fill="#424242">Cast Iron Wall — L = 50 mm, A = 100 cm²</text>
      <text x="475" y="198" text-anchor="middle" font-size="10" fill="#616161">k = 50 W/(m·K) &nbsp; ρ = 7200 kg/m³ &nbsp; cₚ = 460 J/(kg·K)</text>

      <!-- Zone bands -->
      <!-- Zone 1: nodes 1-5 (5 nodes) -->
      <rect x="155" y="55" width="160" height="120" rx="2" fill="#d32f2f" fill-opacity="0.08" stroke="#d32f2f" stroke-width="1" stroke-dasharray="4,2"/>
      <text x="235" y="72" text-anchor="middle" font-size="9" font-weight="600" fill="#c62828">Zone 1</text>
      <text x="235" y="83" text-anchor="middle" font-size="8" fill="#c62828">nodes 1–5</text>

      <!-- Zone 2: nodes 6-10 (5 nodes) -->
      <rect x="315" y="55" width="160" height="120" rx="2" fill="#ff6f00" fill-opacity="0.08" stroke="#ff6f00" stroke-width="1" stroke-dasharray="4,2"/>
      <text x="395" y="72" text-anchor="middle" font-size="9" font-weight="600" fill="#e65100">Zone 2</text>
      <text x="395" y="83" text-anchor="middle" font-size="8" fill="#e65100">nodes 6–10</text>

      <!-- Zone 3: nodes 11-14/15 (4-5 nodes) -->
      <rect x="475" y="55" width="160" height="120" rx="2" fill="#2e7d32" fill-opacity="0.08" stroke="#2e7d32" stroke-width="1" stroke-dasharray="4,2"/>
      <text x="555" y="72" text-anchor="middle" font-size="9" font-weight="600" fill="#2e7d32">Zone 3</text>
      <text x="555" y="83" text-anchor="middle" font-size="8" fill="#2e7d32">nodes 11–15</text>

      <!-- Zone 4: nodes 15/16-20 (5-6 nodes) -->
      <rect x="635" y="55" width="160" height="120" rx="2" fill="#1565c0" fill-opacity="0.08" stroke="#1565c0" stroke-width="1" stroke-dasharray="4,2"/>
      <text x="715" y="72" text-anchor="middle" font-size="9" font-weight="600" fill="#1565c0">Zone 4</text>
      <text x="715" y="83" text-anchor="middle" font-size="8" fill="#1565c0">nodes 16–20</text>

      <!-- 20 node circles -->
      <g font-size="7" text-anchor="middle" fill="#333">
        <!-- nodes 1-5 -->
        <circle cx="171" cy="120" r="8" fill="#ef9a9a" stroke="#c62828" stroke-width="1"/>
        <text x="171" y="123" font-size="7" fill="#333">1</text>
        <circle cx="203" cy="120" r="8" fill="#ef9a9a" stroke="#c62828" stroke-width="1"/>
        <text x="203" y="123" font-size="7" fill="#333">2</text>
        <circle cx="235" cy="120" r="8" fill="#ef9a9a" stroke="#c62828" stroke-width="1"/>
        <text x="235" y="123" font-size="7" fill="#333">3</text>
        <circle cx="267" cy="120" r="8" fill="#ef9a9a" stroke="#c62828" stroke-width="1"/>
        <text x="267" y="123" font-size="7" fill="#333">4</text>
        <circle cx="299" cy="120" r="8" fill="#ef9a9a" stroke="#c62828" stroke-width="1"/>
        <text x="299" y="123" font-size="7" fill="#333">5</text>
        <!-- nodes 6-10 -->
        <circle cx="331" cy="120" r="8" fill="#ffe0b2" stroke="#e65100" stroke-width="1"/>
        <text x="331" y="123" font-size="7" fill="#333">6</text>
        <circle cx="363" cy="120" r="8" fill="#ffe0b2" stroke="#e65100" stroke-width="1"/>
        <text x="363" y="123" font-size="7" fill="#333">7</text>
        <circle cx="395" cy="120" r="8" fill="#ffe0b2" stroke="#e65100" stroke-width="1"/>
        <text x="395" y="123" font-size="7" fill="#333">8</text>
        <circle cx="427" cy="120" r="8" fill="#ffe0b2" stroke="#e65100" stroke-width="1"/>
        <text x="427" y="123" font-size="7" fill="#333">9</text>
        <circle cx="459" cy="120" r="8" fill="#ffe0b2" stroke="#e65100" stroke-width="1"/>
        <text x="459" y="123" font-size="7" fill="#333">10</text>
        <!-- nodes 11-15 -->
        <circle cx="491" cy="120" r="8" fill="#c8e6c9" stroke="#2e7d32" stroke-width="1"/>
        <text x="491" y="123" font-size="7" fill="#333">11</text>
        <circle cx="523" cy="120" r="8" fill="#c8e6c9" stroke="#2e7d32" stroke-width="1"/>
        <text x="523" y="123" font-size="7" fill="#333">12</text>
        <circle cx="555" cy="120" r="8" fill="#c8e6c9" stroke="#2e7d32" stroke-width="1"/>
        <text x="555" y="123" font-size="7" fill="#333">13</text>
        <circle cx="587" cy="120" r="8" fill="#c8e6c9" stroke="#2e7d32" stroke-width="1"/>
        <text x="587" y="123" font-size="7" fill="#333">14</text>
        <circle cx="619" cy="120" r="8" fill="#c8e6c9" stroke="#2e7d32" stroke-width="1"/>
        <text x="619" y="123" font-size="7" fill="#333">15</text>
        <!-- nodes 16-20 -->
        <circle cx="651" cy="120" r="8" fill="#bbdefb" stroke="#1565c0" stroke-width="1"/>
        <text x="651" y="123" font-size="7" fill="#333">16</text>
        <circle cx="683" cy="120" r="8" fill="#bbdefb" stroke="#1565c0" stroke-width="1"/>
        <text x="683" y="123" font-size="7" fill="#333">17</text>
        <circle cx="715" cy="120" r="8" fill="#bbdefb" stroke="#1565c0" stroke-width="1"/>
        <text x="715" y="123" font-size="7" fill="#333">18</text>
        <circle cx="747" cy="120" r="8" fill="#bbdefb" stroke="#1565c0" stroke-width="1"/>
        <text x="747" y="123" font-size="7" fill="#333">19</text>
        <circle cx="779" cy="120" r="8" fill="#bbdefb" stroke="#1565c0" stroke-width="1"/>
        <text x="779" y="123" font-size="7" fill="#333">20</text>
      </g>

      <!-- Conduction arrows between nodes (small) -->
      <g stroke="#888" stroke-width="0.8" stroke-dasharray="2,2">
        <line x1="180" y1="135" x2="294" y2="135"/>
        <line x1="340" y1="135" x2="454" y2="135"/>
        <line x1="500" y1="135" x2="614" y2="135"/>
        <line x1="660" y1="135" x2="774" y2="135"/>
      </g>
      <text x="235" y="150" text-anchor="middle" font-size="7.5" fill="#888">G_cond</text>
      <text x="395" y="150" text-anchor="middle" font-size="7.5" fill="#888">G_cond</text>
      <text x="555" y="150" text-anchor="middle" font-size="7.5" fill="#888">G_cond</text>
      <text x="715" y="150" text-anchor="middle" font-size="7.5" fill="#888">G_cond</text>

      <!-- Coolant-side convection arrow -->
      <line x1="797" y1="115" x2="833" y2="115" stroke="#1565c0" stroke-width="2.5" marker-end="url(#ab)"/>
      <text x="815" y="106" text-anchor="middle" font-size="9" font-weight="600" fill="#1565c0">Gc</text>

      <!-- Coolant side -->
      <rect x="845" y="50" width="95" height="130" rx="6" fill="#e3f2fd" stroke="#1565c0" stroke-width="1.5"/>
      <text x="892" y="42" text-anchor="middle" font-size="11" font-weight="600" fill="#1565c0">COOLANT</text>
      <text x="892" y="108" text-anchor="middle" font-size="20">❄️</text>
      <text x="892" y="135" text-anchor="middle" font-size="9" fill="#0d47a1">T = 300 K</text>

      <!-- Legend -->
      <text x="475" y="215" text-anchor="middle" font-size="9" fill="#757575">
        Zones shown for SVD Thermal Network ROM — other ROMs use different groupings
      </text>
    </svg>
  </div>
</div>

<div class="main">
  <!-- LEFT: PLOTS -->
  <div>
    <div class="card">
      <h3>Training Data</h3>
      <div id="plotTrain" class="plot-box" style="height:320px"></div>
      <div class="data-info">
        Source: <code>data/cfd_training_data.csv</code> — 20-node 1D thermal wall, step+sine input
      </div>
    </div>
  </div>

  <!-- RIGHT: CONTROLS -->
  <div>
    <div class="card">
      <h3>SVD Energy</h3>
      <pre id="energy_text" class="metrics" style="min-height:60px"></pre>
      <div class="data-info" style="margin-top:10px">
        <b>Training:</b> <code>data/cfd_training_data.csv</code><br>
        <b>Validation:</b> <code>data/cfd_validation_data.csv</code><br>
        <b>ROMs:</b> Dyad components in <code>dyad/</code>
      </div>
    </div>
    <div class="card" style="margin-top:10px">
      <h3>ROM Validation</h3>
      <label>ROM type</label>
      <select id="rom_type">
        <option value="POD/DMD">POD/DMDc (SVD snapshots → DMDc dynamics)</option>
        <option value="SVD Network">SVD Thermal Network (SVD → calibrated RC)</option>
        <option value="Neural ODE Network">Neural ODE Network (latent ODE → calibrated RC)</option>
      </select>
      <button class="btn btn-purple" id="btnValidate" onclick="doValidate()">Validate ROM</button>
      <pre id="error_text" class="metrics" style="min-height:80px"></pre>
    </div>
  </div>
</div>

<!-- BOTTOM ROW -->
<div class="bottom">
  <div class="card">
    <h3>Validation — CFD vs ROM</h3>
    <div id="plotComp" class="plot-box" style="height:340px"></div>
  </div>
  <div class="card">
    <h3>ROM Relative Error</h3>
    <div id="plotErr" class="plot-box" style="height:340px"></div>
  </div>
</div>

<div class="status" id="status">Ready. Data loaded, Dyad ROMs compiled. Select a ROM and validate.</div>

<script>
const COLORS = ['#d62728','#ff7f0e','#2ca02c','#1f77b4','#9467bd','#8c564b','#e377c2','#7f7f7f'];

function setStatus(msg) { document.getElementById('status').textContent = msg; }
function setBtn(id, disabled) { document.getElementById(id).disabled = disabled; }

// Load training data on page load
window.addEventListener('load', async () => {
  setStatus('⏳ Loading training data...');
  try {
    const resp = await fetch('/api/training', {
      method: 'POST', headers: {'Content-Type':'application/json'},
      body: JSON.stringify({n_zones: 4})
    });
    const d = await resp.json();

    document.getElementById('energy_text').textContent = d.energy_text;

    const nz = d.zone_temps.length;
    let traces = [{x:d.t, y:d.u, name:'Q_in [W]', yaxis:'y2',
                   line:{color:'black', width:2}}];
    for (let z=0; z<nz; z++) {
      traces.push({x:d.t, y:d.zone_temps[z], name:'Zone '+(z+1),
                   line:{color:COLORS[z], width:2}});
    }
    Plotly.react('plotTrain', traces, {
      xaxis:{title:'Time [s]'}, yaxis:{title:'Temperature [K]'},
      yaxis2:{title:'Q_in [W]', side:'right', overlaying:'y', showgrid:false},
      legend:{x:0.01, y:0.99, bgcolor:'rgba(255,255,255,0.8)'},
      height:300, margin:{t:10,b:50}
    });

    setStatus('✅ Data loaded, Dyad ROMs compiled. Select a ROM type and validate.');
  } catch(e) { setStatus('❌ ' + e.message); }
});

async function doValidate() {
  setBtn('btnValidate', true);
  setStatus('⏳ Simulating Dyad ROM...');
  try {
    const resp = await fetch('/api/validate', {
      method: 'POST', headers: {'Content-Type':'application/json'},
      body: JSON.stringify({
        rom_type: document.getElementById('rom_type').value,
        n_zones: 4
      })
    });
    const d = await resp.json();
    if (d.error) { setStatus('⚠️ ' + d.error); return; }

    document.getElementById('error_text').textContent = d.error_text;

    // Comparison plot
    const nz = d.cfd_zones.length;
    let cTraces = [];
    for (let z=0; z<nz; z++) {
      cTraces.push({x:d.t, y:d.cfd_zones[z], name:'CFD Zone '+(z+1),
                    line:{color:COLORS[z], width:2.5}, legendgroup:'z'+z});
      cTraces.push({x:d.t, y:d.rom_zones[z], name:'ROM Zone '+(z+1),
                    line:{color:COLORS[z], width:2, dash:'dash'}, legendgroup:'z'+z});
    }
    Plotly.react('plotComp', cTraces, {
      title:{text:'CFD vs ' + d.method, font:{size:13}},
      xaxis:{title:'Time [s]'}, yaxis:{title:'Temperature [K]'},
      legend:{x:0.01, y:0.99, bgcolor:'rgba(255,255,255,0.8)'},
      height:320, margin:{t:35,b:50}
    });

    // Error plot
    let eTraces = [];
    for (let z=0; z<nz; z++) {
      eTraces.push({x:d.t, y:d.err_zones[z], name:'Zone '+(z+1),
                    line:{color:COLORS[z], width:2}});
    }
    eTraces.push({x:[d.t[0],d.t[d.t.length-1]], y:[0,0], mode:'lines',
                  line:{color:'gray', width:1, dash:'dash'}, showlegend:false});
    Plotly.react('plotErr', eTraces, {
      title:{text:'ROM Relative Error', font:{size:13}},
      xaxis:{title:'Time [s]'}, yaxis:{title:'Relative Error [%]'},
      legend:{x:0.01, y:0.99, bgcolor:'rgba(255,255,255,0.8)'},
      height:320, margin:{t:35,b:50}
    });

    setStatus('✅ ' + d.method + ' — Overall RMS: ' + d.overall_rms + ' K');
  } catch(e) { setStatus('❌ ' + e.message); }
  finally { setBtn('btnValidate', false); }
}
</script>
</body>
</html>
"""

# ════════════════════════════════════════════════════════════════
#  HTTP Router
# ════════════════════════════════════════════════════════════════

function router(req)
    if req.method == "GET" && req.target == "/"
        return HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], INDEX_HTML)
    elseif req.method == "POST" && req.target == "/api/training"
        return handle_training(req)
    elseif req.method == "POST" && req.target == "/api/validate"
        return handle_validate(req)
    else
        return HTTP.Response(404, "Not found")
    end
end

# ════════════════════════════════════════════════════════════════
#  Start server
# ════════════════════════════════════════════════════════════════

port = parse(Int, get(ENV, "PORT", "9000"))
println("\n" * "=" ^ 60)
println("  Dashboard ready at http://localhost:$port")
println("  Data:  $(DATA_DIR)")
println("  ROMs:  Dyad components (compiled at startup)")
println("=" ^ 60 * "\n")
HTTP.serve(router, "0.0.0.0", port)
