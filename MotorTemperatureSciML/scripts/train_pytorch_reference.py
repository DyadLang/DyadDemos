# /// script
# requires-python = ">=3.10"
# dependencies = [
#     "torch>=2.2",
#     "pandas>=2.0",
#     "numpy>=1.26",
# ]
#
# [[tool.uv.index]]
# name = "pytorch-cpu"
# url = "https://download.pytorch.org/whl/cpu"
# explicit = true
#
# [tool.uv.sources]
# torch = { index = "pytorch-cpu" }
# ///
"""
Reference PyTorch Thermal Neural Network, trained on profile 17 only.

A port of the training and evaluation cells of `TNN_pytorch.ipynb` from
github.com/wkirgsn/thermal-nn (model code verbatim), restricted to the single
profile this demo trains on, so the Dyad calibration can be compared with the
reference implementation at equal data. It reads the profile CSVs shipped in
assets/data/ (the notebook's preprocessing is reproduced with the same max-abs
constants as dyad/Thermal/Normalizer.dyad) and writes
assets/data/pytorch_profile_<id>.csv, the free-running predictions that
scripts/validate_calibration.jl overlays.

Run from the package root (uv creates the CPU-only environment on first use):

    uv run scripts/train_pytorch_reference.py
    uv run scripts/train_pytorch_reference.py --epochs 100 --threads 8

Without uv: `pip install -r scripts/requirements.txt` and run with `python`.

Training follows the notebook: Adam at 1e-3, halved at epoch 75; truncated
backpropagation through time over 512-sample chunks, with the hidden state
carried (detached) from one chunk to the next and reset from the measurements
only at the start of each epoch; 100 epochs; no gradient clipping. Evaluation
runs the model free over each whole profile from its first measured sample.
"""
import argparse
import time
import warnings
from pathlib import Path
from typing import List, Tuple

import numpy as np
import pandas as pd
import torch
import torch.nn as nn
import torch.optim as optim
from torch import Tensor
from torch.nn import Parameter as TorchParam

# ── Data ──────────────────────────────────────────────────────────────────────

TRAIN_PROFILE = 17
PROFILES = (17, 60, 62, 74)
DT = 0.5  # s

INPUT_COLS = ["u_q", "coolant", "u_d", "motor_speed", "i_d", "i_q", "ambient", "torque", "i_s", "u_s"]
TARGET_COLS = ["pm", "stator_yoke", "stator_tooth", "stator_winding"]
TEMPERATURE_COLS = TARGET_COLS + ["ambient", "coolant"]

# The notebook divides temperatures by 200 and every other signal by its
# max-abs over the full 69-profile dataset. i_s / u_s are already derived from
# the normalised currents and voltages in the shipped CSVs.
MAX_TEMP = 200.0
MAX_ABS = {
    "u_q": 162.266159057617,
    "u_d": 164.791656494141,
    "motor_speed": 1411.75,
    "i_d": 399.7197265625,
    "i_q": 369.958343505859,
    "torque": 2243.25,
}


def load_profile(data_dir: Path, pid: int) -> pd.DataFrame:
    df = pd.read_csv(data_dir / f"profile_{pid}.csv")
    for c in TEMPERATURE_COLS:
        df[c] = df[c] / MAX_TEMP
    for c, m in MAX_ABS.items():
        df[c] = df[c] / m
    return df


def to_tensor(df: pd.DataFrame) -> Tensor:
    """(T, 1, n_inputs + n_targets) float32, batch dimension = one profile."""
    arr = df[INPUT_COLS + TARGET_COLS].to_numpy(dtype=np.float32)
    return torch.from_numpy(arr[:, None, :])


# ── Model (verbatim from the notebook, sizes passed in instead of read from globals) ──

class DiffEqLayer(nn.Module):
    def __init__(self, cell, *cell_args):
        super().__init__()
        self.cell = cell(*cell_args)

    def forward(self, input: Tensor, state: Tensor) -> Tuple[Tensor, Tensor]:
        inputs = input.unbind(0)
        outputs = torch.jit.annotate(List[Tensor], [])
        for i in range(len(inputs)):
            out, state = self.cell(inputs[i], state)
            outputs += [out]
        return torch.stack(outputs), state


class TNNCell(nn.Module):
    def __init__(self, n_inputs: int, n_targets: int, temp_idcs: List[int], n_temps: int):
        super().__init__()
        self.sample_time = DT
        self.output_size = n_targets
        self.caps = TorchParam(torch.Tensor(self.output_size))
        nn.init.normal_(self.caps, mean=-9.2, std=0.5)
        n_conds = int(0.5 * n_temps * (n_temps - 1))
        self.conductance_net = nn.Sequential(nn.Linear(n_inputs + n_targets, n_conds), nn.Sigmoid())
        adj_mat = np.zeros((n_temps, n_temps), dtype=int)
        adj_idx_arr = np.ones_like(adj_mat)
        triu_idx = np.triu_indices(n_temps, 1)
        adj_idx_arr = adj_idx_arr[triu_idx].ravel()
        adj_mat[triu_idx] = np.cumsum(adj_idx_arr) - 1
        adj_mat += adj_mat.T
        self.adj_mat = torch.from_numpy(adj_mat[:n_targets, :]).type(torch.int64)
        self.n_temps = n_temps
        self.ploss = nn.Sequential(
            nn.Linear(n_inputs + n_targets, 16),
            nn.Tanh(),
            nn.Linear(16, n_targets),
        )
        self.temp_idcs = temp_idcs

    def forward(self, inp: Tensor, hidden: Tensor) -> Tuple[Tensor, Tensor]:
        prev_out = hidden
        temps = torch.cat([prev_out, inp[:, self.temp_idcs]], dim=1)
        sub_nn_inp = torch.cat([inp, prev_out], dim=1)
        conducts = torch.abs(self.conductance_net(sub_nn_inp))
        power_loss = torch.abs(self.ploss(sub_nn_inp))
        temp_diffs = torch.sum(
            (temps.unsqueeze(1) - prev_out.unsqueeze(-1)) * conducts[:, self.adj_mat],
            dim=-1,
        )
        out = prev_out + self.sample_time * torch.exp(self.caps) * (temp_diffs + power_loss)
        return prev_out, torch.clip(out, -1, 5)


def build_model() -> nn.Module:
    temp_idcs = [i for i, c in enumerate(INPUT_COLS) if c in TEMPERATURE_COLS]  # coolant, ambient
    model = DiffEqLayer(TNNCell, len(INPUT_COLS), len(TARGET_COLS), temp_idcs, len(TEMPERATURE_COLS))
    # The notebook scripts the model with TorchScript; recent torch versions
    # warn that TorchScript is deprecated, which is noise here.
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", FutureWarning)
        return torch.jit.script(model)


# ── Training (the notebook's loop) ────────────────────────────────────────────

def train(model: nn.Module, data: Tensor, epochs: int, tbptt: int, lr: float,
          lr_decay_epoch: int) -> Tuple[float, list]:
    n_in, n_out = len(INPUT_COLS), len(TARGET_COLS)
    T = data.shape[0]
    n_batches = int(np.ceil(T / tbptt))
    sample_weights = torch.ones(T, data.shape[1])
    loss_func = nn.MSELoss(reduction="none")
    opt = optim.Adam(model.parameters(), lr=lr)
    history = []
    t0 = time.perf_counter()
    for epoch in range(epochs):
        losses = []
        hidden = data[0, :, -n_out:]  # first state is the measured temperature
        for i in range(n_batches):
            lo, hi = i * tbptt, min((i + 1) * tbptt, T)
            model.zero_grad()
            # the state carries over from the previous chunk; gradients do not
            output, hidden = model(data[lo:hi, :, :n_in], hidden.detach())
            target = data[lo:hi, :, -n_out:]
            loss = loss_func(output, target)
            sw = sample_weights[lo:hi, :, None]
            denom = sample_weights[lo:hi, :].sum()
            loss = (loss * sw / denom).sum().mean()
            loss.backward()
            opt.step()
            losses.append(loss.item())
        if epoch == lr_decay_epoch:
            for group in opt.param_groups:
                group["lr"] *= 0.5
        history.append(float(np.mean(losses)))
        if (epoch + 1) % 10 == 0 or epoch == 0:
            print(f"  epoch {epoch + 1:3d}/{epochs}   loss {history[-1]:.3e}   "
                  f"elapsed {time.perf_counter() - t0:6.1f} s", flush=True)
    return time.perf_counter() - t0, history


# ── Evaluation: free run over a whole profile from its first measured sample ──

@torch.no_grad()
def predict(model: nn.Module, data: Tensor) -> np.ndarray:
    n_in, n_out = len(INPUT_COLS), len(TARGET_COLS)
    output, _ = model(data[:, :, :n_in], data[0, :, -n_out:])
    return output[:, 0, :].numpy() * MAX_TEMP


def main():
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--epochs", type=int, default=100)
    ap.add_argument("--tbptt", type=int, default=512, help="TBPTT chunk length (samples)")
    ap.add_argument("--lr", type=float, default=1e-3)
    ap.add_argument("--lr-decay-epoch", type=int, default=75, help="epoch after which the LR is halved")
    ap.add_argument("--seed", type=int, default=0)
    ap.add_argument("--threads", type=int, default=None, help="torch CPU threads (default: torch's)")
    ap.add_argument("--data-dir", type=Path, default=here.parent / "assets" / "data")
    ap.add_argument("--out-dir", type=Path, default=None,
                    help="where to write pytorch_profile_<id>.csv (default: --data-dir)")
    ap.add_argument("--no-export", action="store_true", help="only train and report, write nothing")
    args = ap.parse_args()
    out_dir = args.out_dir or args.data_dir

    if args.threads:
        torch.set_num_threads(args.threads)
    torch.manual_seed(args.seed)
    np.random.seed(args.seed)

    profiles = {pid: load_profile(args.data_dir, pid) for pid in PROFILES}
    train_data = to_tensor(profiles[TRAIN_PROFILE])
    model = build_model()
    n_params = sum(p.numel() for p in model.parameters())
    n_batches = int(np.ceil(train_data.shape[0] / args.tbptt))
    print(f"Training profile {TRAIN_PROFILE}: {train_data.shape[0]} samples, "
          f"{n_batches} TBPTT chunks of {args.tbptt} per epoch, {args.epochs} epochs "
          f"= {n_batches * args.epochs} updates; {n_params} parameters; "
          f"torch threads {torch.get_num_threads()}", flush=True)

    elapsed, history = train(model, train_data, args.epochs, args.tbptt, args.lr, args.lr_decay_epoch)
    print(f"\nTraining wall-clock: {elapsed:.1f} s  ({elapsed / args.epochs:.2f} s / epoch, "
          f"{1000 * elapsed / (n_batches * args.epochs):.1f} ms / update)   final training loss {history[-1]:.3e}")

    model.eval()
    print("\nFree-running RMS error [°C], channels pm / yoke / tooth / winding")
    for pid, df in profiles.items():
        pred = predict(model, to_tensor(df))
        meas = df[TARGET_COLS].to_numpy() * MAX_TEMP
        rms = np.sqrt(np.mean((pred - meas) ** 2, axis=0))
        tag = "training" if pid == TRAIN_PROFILE else "held out"
        print(f"  profile {pid:2d} ({tag:8s})  " + "  ".join(f"{r:7.2f}" for r in rms))
        if not args.no_export:
            out = pd.DataFrame({"time": df["time"].to_numpy()})
            for j, c in enumerate(TARGET_COLS):
                out[f"{c}_pred"] = pred[:, j]
            out_dir.mkdir(parents=True, exist_ok=True)
            out.to_csv(out_dir / f"pytorch_profile_{pid}.csv", index=False)
    if not args.no_export:
        print(f"\nPredictions written to {out_dir}/pytorch_profile_<id>.csv")


if __name__ == "__main__":
    main()
