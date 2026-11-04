#!/usr/bin/env python3
"""Run actual Capture entry-point UI checks on a disposable, signed-out simulator.

Requires Xcode and xcodegen. Device pose is controlled in Device Hub, never faked.
Evidence is written only to --output; the generated test app uses a distinct ID.
"""
import argparse
from pathlib import Path
import subprocess
import tempfile

SPEC = "name: CaptureStartupRegression\noptions:\n  deploymentTarget:\n    iOS: '26.0'\nsettings:\n  base:\n    SWIFT_VERSION: '5.10'\n    CODE_SIGNING_ALLOWED: NO\ntargets:\n  Core:\n    type: library.static\n    platform: iOS\n    sources: ['{repo}/Sources/UnliRiceCore']\n    settings:\n      base:\n        PRODUCT_MODULE_NAME: UnliRiceCore\n  CaptureStartup:\n    type: application\n    platform: iOS\n    sources:\n      - path: '{repo}/Sources/UnliRiceCapture'\n        excludes: [Resources]\n      - path: '{repo}/Sources/UnliRiceCapture/Resources'\n        buildPhase: resources\n    dependencies: [{target: Core}]\n    settings:\n      base:\n        PRODUCT_BUNDLE_IDENTIFIER: com.calmdownoscar.unlirice.startupregression\n        GENERATE_INFOPLIST_FILE: YES\n        INFOPLIST_KEY_UILaunchScreen_Generation: YES\n        TARGETED_DEVICE_FAMILY: '1,2'\n  StartupTests:\n    type: bundle.ui-testing\n    platform: iOS\n    sources: ['{repo}/Tests/UnliRiceCaptureUITests']\n    dependencies: [{target: CaptureStartup}]\n    settings:\n      base:\n        PRODUCT_BUNDLE_IDENTIFIER: com.calmdownoscar.unlirice.startupregression.tests\n        GENERATE_INFOPLIST_FILE: YES\nschemes:\n  CaptureStartup:\n    build:\n      targets:\n        CaptureStartup: all\n        StartupTests: [test]\n    test:\n      targets: [StartupTests]\n"

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--device", required=True, help="Disposable simulator UDID")
parser.add_argument("--mode", choices=["ordinary", "closed", "open"], default="ordinary")
parser.add_argument("--output", type=Path)
args = parser.parse_args()
repo = Path(__file__).resolve().parents[1]
output = args.output.resolve() if args.output else Path(tempfile.mkdtemp(prefix="capture-startup-"))
output.mkdir(parents=True, exist_ok=True)
result = output / "Result.xcresult"
if result.exists():
    parser.error("Output already contains Result.xcresult; choose a new evidence directory")
spec = output / "project.yml"
spec.write_text(SPEC.replace("{repo}", str(repo)))
subprocess.run(["xcodegen", "generate", "--spec", str(spec)], check=True)
method = {"ordinary": "testStandaloneNavigation", "closed": "testClosedDuo", "open": "testOpenDuo"}[args.mode]
command = ["xcodebuild", "-project", str(output / "CaptureStartupRegression.xcodeproj"),
           "-scheme", "CaptureStartup", "-destination", "platform=iOS Simulator,id=" + args.device,
           "-derivedDataPath", str(output / "Derived"), "-resultBundlePath", str(result),
           "-only-testing:StartupTests/StartupTests/" + method, "test"]
with (output / "test.log").open("w") as log:
    completed = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT)
print("Evidence:", output, flush=True)
print("PASS" if completed.returncode == 0 else "FAIL", "exit", completed.returncode, flush=True)
raise SystemExit(completed.returncode)
