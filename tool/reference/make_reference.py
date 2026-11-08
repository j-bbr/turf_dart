"""Computes shapely reference results for the reference cases.

Reads every test/examples/shapely_reference/in/<case>.geojson (written by
tool/reference/make_inputs.dart), applies the operations in order - "op":
"intersect", "difference" or "union" - and writes the result to
test/examples/shapely_reference/out/<case>.geojson as a Feature (geometry null when
the result becomes empty), with the planar area in square degrees.

Usage (shapely 2.x):

    python3 -m pip install shapely
    python3 tool/reference/make_reference.py
"""
import json
import pathlib

import shapely
from shapely.geometry import mapping, shape

ROOT = pathlib.Path(__file__).resolve().parents[2]
IN_DIR = ROOT / "test" / "examples" / "shapely_reference" / "in"
OUT_DIR = ROOT / "test" / "examples" / "shapely_reference" / "out"


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for path in sorted(IN_DIR.glob("*.geojson")):
        fc = json.loads(path.read_text())
        features = fc["features"]
        area = shape(features[0]["geometry"])
        for feature in features[1:]:
            region = shape(feature["geometry"])
            op = feature["properties"]["op"]
            if op == "intersect":
                area = area.intersection(region)
            elif op == "difference":
                area = area.difference(region)
            elif op == "union":
                area = area.union(region)
            else:
                raise ValueError(f"{path.name}: unknown op {op}")
        # keep only polygonal parts (intersections can add lines or points)
        if area.geom_type == "GeometryCollection":
            area = shapely.union_all(
                [g for g in area.geoms if g.geom_type in ("Polygon", "MultiPolygon")]
            )
        result = {
            "type": "Feature",
            "properties": {
                "shapely": shapely.__version__,
                "area": area.area,
                "polygons": 0 if area.is_empty else len(getattr(area, "geoms", [area])),
            },
            "geometry": None if area.is_empty else mapping(shapely.geometry.polygon.orient(area) if area.geom_type == "Polygon" else area),
        }
        out = OUT_DIR / path.name
        out.write_text(json.dumps(result, indent=2) + "\n")
        print(f"wrote {out.relative_to(ROOT)}: area {area.area}")


if __name__ == "__main__":
    main()
