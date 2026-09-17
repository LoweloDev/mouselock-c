#!/usr/bin/env python3
"""Build a local ad-hoc signed app; does not grant permissions or launch it."""
import argparse
import pathlib
import plistlib
import shutil
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("output", type=pathlib.Path, help="Destination ending in .app")
args = parser.parse_args()
root = pathlib.Path(__file__).resolve().parent
app = args.output.resolve()
if app.suffix != ".app":
    parser.error("destination must end in .app")
subprocess.run(["make", "all", "test"], cwd=root, check=True)
executables = app / "Contents" / "MacOS"
executables.mkdir(parents=True, exist_ok=True)
shutil.copyfile(root / "build" / "mouselock", executables / "mouselock")
(executables / "mouselock").chmod(0o755)
with (app / "Contents" / "Info.plist").open("wb") as handle:
    plistlib.dump({
        "CFBundleIdentifier": "dev.lowelodev.mouselock-hid",
        "CFBundleName": "MouseLock HID",
        "CFBundleDisplayName": "MouseLock HID",
        "CFBundleExecutable": "mouselock",
        "CFBundlePackageType": "APPL",
        "CFBundleVersion": "3",
        "CFBundleShortVersionString": "0.3.0",
        "LSUIElement": True,
        "NSInputMonitoringUsageDescription": "Read only the gaming mouse HID reports while testing League cursor confinement.",
    }, handle)
# Finder can attach metadata when the previously built bundle is browsed.
# Remove only the two metadata attributes forbidden by codesign. Keep any
# quarantine and other security attributes intact.
for path in [app, *app.rglob("*")]:
    if path.is_symlink():
        continue
    attributes = subprocess.run(["xattr", str(path)], capture_output=True,
                                text=True, check=True).stdout.splitlines()
    for name in ("com.apple.FinderInfo", "com.apple.ResourceFork"):
        if name in attributes:
            subprocess.run(["xattr", "-d", name, str(path)], check=True)
subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
print(app)
print("Starts enabled for League, without a timeout. Use --paused or --seconds N for testing.")
print("Rebuilding changes the ad-hoc signature; macOS may require renewed permissions.")
