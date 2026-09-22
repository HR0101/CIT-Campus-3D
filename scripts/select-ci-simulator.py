"""Select an available iPhone running iOS 26.5 or later for xcodebuild."""
import json
import re
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    runtimes = json.load(source)["devices"]
candidates = []
for runtime, devices in runtimes.items():
    match = re.search(r"\.iOS-(\d+)-(\d+)(?:-(\d+))?$", runtime)
    if not match:
        continue
    version = tuple(int(part or 0) for part in match.groups())
    if version < (26, 5, 0):
        continue
    for device in devices:
        if device.get("isAvailable") and device["name"].startswith("iPhone"):
            candidates.append((version, device["name"], device["udid"]))
if not candidates:
    sys.exit("No available iPhone simulator with iOS >= 26.5")
print(f"id={max(candidates)[2]}")
