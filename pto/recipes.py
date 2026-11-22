"""Run the official tag's test and build steps as local Actions on the prepared source."""
import json
import subprocess
import sys
from pathlib import Path

import yaml


def write_action(commit, workflow, job):
    path = f".github/workflows/{workflow}.yml"
    source = subprocess.check_output(["git", "show", f"{commit}:{path}"], text=True)
    spec = yaml.safe_load(source)["jobs"][job]
    steps = []
    for step in spec["steps"]:
        action = step.get("uses", "").split("@")[0]
        if action in ("actions/checkout", "actions/upload-artifact"):
            continue  # Checkout and delivery are owned by the fork.
        if "run" in step:
            step.setdefault("shell", spec.get("defaults", {}).get("run", {}).get("shell", "bash"))
        if spec.get("env"):
            step["env"] = {**spec["env"], **step.get("env", {})}
        steps.append(step)
        if job == "test" and action == "actions/setup-go":
            steps.append({
                "name": "Apply and test the PTO patch",
                "shell": "bash",
                "run": 'bash pto/prepare-quic.sh "$RUNNER_TEMP/pto-work"\n'
                       'export GOWORK="$RUNNER_TEMP/pto-work/go.work"\n'
                       'echo "GOWORK=$GOWORK" >> "$GITHUB_ENV"\n'
                       'go test github.com/apernet/quic-go/internal/{utils,ackhandler}',
            })
    dest = Path(".pto-actions") / job
    dest.mkdir(parents=True, exist_ok=True)
    (dest / "action.yml").write_text(json.dumps({
        "name": f"Upstream {job}", "description": f"{path} at {commit}",
        "runs": {"using": "composite", "steps": steps},
    }, indent=2) + "\n")


if __name__ == "__main__":
    write_action(sys.argv[1], "test", "test")
    write_action(sys.argv[1], "build-common", "build")
