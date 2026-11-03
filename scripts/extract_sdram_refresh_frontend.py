"""Extract the readable production refresh scheduler for ModelSim checks.

The encrypted command encoder is deliberately excluded; this fixture checks
the timer, request and acknowledgement logic, not physical SDRAM commands.
"""
from pathlib import Path

root = Path(__file__).resolve().parents[1]
source = root / "fpga/user_source/hdl_source/include/sdr_init_ref.enc.v"
text = source.read_text(encoding="utf-8")
front, marker, _ = text.partition("`pragma protect begin_protected")
if not marker or "assign Sdr_ref_req=ref_req | App_ref_req;" not in front:
    raise SystemExit("Unexpected production refresh scheduler structure")
front = front.replace('"../user_source/hdl_source/include/global_def.v"', '"global_def.v"')
output = root / "out/sdram_refresh_frontend.v"
output.parent.mkdir(exist_ok=True)
output.write_text(front + "\nendmodule\n", encoding="utf-8")
