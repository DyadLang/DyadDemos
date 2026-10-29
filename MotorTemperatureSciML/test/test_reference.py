"""Run with the same Python environment as scripts/train_pytorch_reference.py."""
import importlib.util
from pathlib import Path
import unittest

import pandas as pd

SCRIPT = Path(__file__).resolve().parents[1] / "scripts" / "train_pytorch_reference.py"
spec = importlib.util.spec_from_file_location("reference", SCRIPT)
reference = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reference)


class TrainingWindowTests(unittest.TestCase):
    def test_boundary_is_included_and_tail_is_excluded(self):
        df = pd.DataFrame({"time": [0.0, 7199.5, 7200.0, 7200.5],
                           "pm": [20.0, 40.0, 41.0, 999.0]})
        train = reference.training_window(df, reference.TRAIN_HORIZON_S)
        self.assertEqual(train.time.tolist(), [0.0, 7199.5, 7200.0])
        self.assertNotIn(999.0, train.pm.to_numpy())
        self.assertEqual(len(df), 4)  # Full evaluation data is preserved.

    def test_shipped_profile_matches_dyad_horizon(self):
        df = pd.read_parquet(SCRIPT.parents[1] / "assets/data/profile_17.parquet")
        train = reference.training_window(df, reference.TRAIN_HORIZON_S)
        self.assertEqual(len(train), 14401)
        self.assertEqual(train.time.iloc[-1], 7200.0)
        self.assertGreater(df.time.iloc[-1], 7200.0)

    def test_incomplete_profile_is_rejected(self):
        with self.assertRaises(ValueError):
            reference.training_window(pd.DataFrame({"time": [0.0, 1.0]}), 7200.0)


if __name__ == "__main__":
    unittest.main()
