"""Run repository ModelSim checks sequentially and retain an auditable summary."""

import argparse
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True, help="New folder name under out/")
    parser.add_argument("--vsim", default="D:/intelFPGA/18.1/modelsim_ase/win32aloem/vsim.exe")
    parser.add_argument("--timeout", type=int, default=300, help="Seconds per check")
    args = parser.parse_args()
    if not re.fullmatch(r"[A-Za-z0-9_-]+", args.output) or args.timeout <= 0:
        parser.error("output must be a folder name and timeout must be positive")
    root = Path(__file__).resolve().parents[1]
    output = root / "out" / args.output
    if output.exists():
        parser.error("output folder already exists")
    executable = shutil.which(args.vsim)
    if executable is None:
        parser.error("ModelSim executable not found")
    checks = sorted((root / "sim").glob("run_*.do"))
    if not checks:
        parser.error("no ModelSim checks found")
    output.mkdir(parents=True)
    results = []
    for check in checks:
        log = output / (check.stem + ".log")
        # Existing .do files share the work library, so never run concurrently.
        with log.open("w", encoding="utf-8") as stream:
            try:
                result = subprocess.run(
                    [executable, "-c", "-do", check.relative_to(root).as_posix()],
                    cwd=root, stdout=stream, stderr=subprocess.STDOUT,
                    timeout=args.timeout, check=False,
                )
                code = result.returncode
            except subprocess.TimeoutExpired:
                code = -1
                stream.write("\nREGRESSION_TIMEOUT\n")
        transcript = log.read_text(encoding="utf-8", errors="replace")
        passed = code == 0 and "TEST_PASS" in transcript and not re.search(
            r"TEST_FAIL|\*\* (?:Error|Fatal)|REGRESSION_TIMEOUT", transcript
        )
        results.append({"test": check.name, "exit": code, "passed": passed})
        print(f"{'PASS' if passed else 'FAIL'} {check.name}", flush=True)
        (output / "results.json").write_text(
            json.dumps(results, indent=2) + "\n", encoding="utf-8"
        )
    count = sum(item["passed"] for item in results)
    print(f"REGRESSION_RESULT {count}/{len(results)}", flush=True)
    return 0 if count == len(results) else 1


if __name__ == "__main__":
    sys.exit(main())
