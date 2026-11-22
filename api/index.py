import sys
from pathlib import Path

# Daftarkan direktori backend agar modul main dan helper terbaca
ROOT_DIR = Path(__file__).resolve().parent.parent
BACKEND_DIR = ROOT_DIR / "backend"

sys.path.insert(0, str(BACKEND_DIR))
sys.path.insert(0, str(ROOT_DIR))

from main import app  # noqa: E402
