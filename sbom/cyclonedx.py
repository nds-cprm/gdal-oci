"""Writes a CycloneDX SBOM for the components built from source or downloaded outside apt.

Usage: cyclonedx.py <output.cdx.json> <name|version|purl|cpe|license> ...
(cpe and license may be empty; license is an SPDX id or a free-form name)

The files go to ${BASE_DIR}/share/sbom, where the BuildKit SBOM scanner (Syft) picks them up and
merges their components into the image SBOM attestation. Grype matches them by CPE.
No timestamp or serial number, so the output only changes when a version changes (layer cache).
"""
import json
import re
import sys


def component(spec):
    name, version, purl, cpe, license_ = spec.split("|")
    comp = {"type": "library", "name": name, "version": version, "purl": purl}
    if cpe:
        comp["cpe"] = cpe
    if license_:
        key = "id" if re.fullmatch(r"[A-Za-z0-9.+-]+", license_) else "name"
        comp["licenses"] = [{"license": {key: license_}}]
    return comp


def main():
    output, specs = sys.argv[1], sys.argv[2:]
    if not specs:
        sys.exit("usage: cyclonedx.py <output.cdx.json> <name|version|purl|cpe|license> ...")
    bom = {
        "bomFormat": "CycloneDX",
        "specVersion": "1.6",
        "version": 1,
        "components": [component(s) for s in specs],
    }
    with open(output, "w", encoding="utf-8") as f:
        json.dump(bom, f, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
