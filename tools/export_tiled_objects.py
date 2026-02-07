#!/usr/bin/env python3
"""Flatten Tiled exports into a single JSON with points, rectangles, polygons, and images."""

from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Mapping

try:
    import orjson

    def load_json(path: Path) -> Any:
        return orjson.loads(path.read_bytes())

    def dump_json(obj: Any, path: Path) -> None:
        path.write_bytes(orjson.dumps(obj, option=orjson.OPT_INDENT_2))

except ImportError:
    import json

    def load_json(path: Path) -> Any:
        return json.loads(path.read_text())

    def dump_json(obj: Any, path: Path) -> None:
        path.write_text(json.dumps(obj, indent=2))


DEFAULT_INPUT = Path("tiled/objects.json")
DEFAULT_OUTPUT = Path("resources/json/layers.json")


# ── Output dataclasses ──────────────────────────────────────────────────────────


@dataclass
class Point2D:
    x: float = 0.0
    y: float = 0.0


@dataclass
class PointEntry:
    position: Point2D
    name: str = ""
    rotation: float = 0.0


@dataclass
class RectangleEntry:
    position: Point2D
    width: float = 0.0
    height: float = 0.0
    name: str = ""
    rotation: float = 0.0


@dataclass
class PolygonEntry:
    vertices: list[Point2D]
    closed: bool = True
    name: str = ""
    rotation: float = 0.0


@dataclass
class ImageEntry:
    name: str = ""
    image: str = ""
    position: Point2D = field(default_factory=Point2D)
    width: float = 0.0
    height: float = 0.0
    index: int | None = None


@dataclass
class LayerSummary:
    points: list[PointEntry] = field(default_factory=list)
    rectangles: list[RectangleEntry] = field(default_factory=list)
    polygons: list[PolygonEntry] = field(default_factory=list)
    images: list[ImageEntry] = field(default_factory=list)


# ── Input dataclasses (Tiled JSON) ──────────────────────────────────────────────


@dataclass
class TiledProperty:
    name: str = ""
    value: Any = None
    type: str = ""

    @classmethod
    def from_raw(cls, raw: Mapping[str, Any]) -> TiledProperty:
        return cls(
            name=raw.get("name", ""),
            value=raw.get("value"),
            type=raw.get("type", ""),
        )


@dataclass
class TiledPolygonVertex:
    x: float = 0.0
    y: float = 0.0

    @classmethod
    def from_raw(cls, raw: Mapping[str, Any]) -> TiledPolygonVertex:
        return cls(x=float(raw.get("x", 0)), y=float(raw.get("y", 0)))


@dataclass
class TiledObject:
    name: str = ""
    x: float = 0.0
    y: float = 0.0
    width: float = 0.0
    height: float = 0.0
    rotation: float = 0.0
    point: bool = False
    polygon: list[TiledPolygonVertex] = field(default_factory=list)
    closed: bool = True

    @classmethod
    def from_raw(cls, raw: Mapping[str, Any]) -> TiledObject:
        return cls(
            name=raw.get("name", ""),
            x=float(raw.get("x", 0)),
            y=float(raw.get("y", 0)),
            width=float(raw.get("width", 0)),
            height=float(raw.get("height", 0)),
            rotation=float(raw.get("rotation", 0)),
            point=bool(raw.get("point", False)),
            polygon=[TiledPolygonVertex.from_raw(v) for v in raw.get("polygon", [])],
            closed=bool(raw.get("closed", True)),
        )


@dataclass
class TiledLayer:
    name: str = ""
    type: str = ""
    objects: list[TiledObject] = field(default_factory=list)
    image: str = ""
    x: float = 0.0
    y: float = 0.0
    offsetx: float | None = None
    offsety: float | None = None
    width: float = 0.0
    height: float = 0.0
    imagewidth: float = 0.0
    imageheight: float = 0.0
    properties: list[TiledProperty] = field(default_factory=list)

    @classmethod
    def from_raw(cls, raw: Mapping[str, Any]) -> TiledLayer:
        return cls(
            name=raw.get("name", ""),
            type=raw.get("type", ""),
            objects=[TiledObject.from_raw(o) for o in raw.get("objects", [])],
            image=raw.get("image", ""),
            x=float(raw.get("x", 0)),
            y=float(raw.get("y", 0)),
            offsetx=raw.get("offsetx"),
            offsety=raw.get("offsety"),
            width=float(raw.get("width", 0)),
            height=float(raw.get("height", 0)),
            imagewidth=float(raw.get("imagewidth", 0)),
            imageheight=float(raw.get("imageheight", 0)),
            properties=[TiledProperty.from_raw(p) for p in raw.get("properties", [])],
        )


@dataclass
class TiledDocument:
    layers: list[TiledLayer] = field(default_factory=list)

    @classmethod
    def from_raw(cls, raw: Mapping[str, Any]) -> TiledDocument:
        return cls(
            layers=[
                TiledLayer.from_raw(layer)
                for layer in raw.get("layers", [])
                if isinstance(layer, dict)
            ]
        )


# ── Conversion logic ────────────────────────────────────────────────────────────


def translate_point(base_x: float, base_y: float, vertex: TiledPolygonVertex | None = None) -> Point2D:
    if vertex is None:
        return Point2D(x=base_x, y=base_y)
    return Point2D(x=base_x + vertex.x, y=base_y + vertex.y)


def parse_point(obj: TiledObject) -> PointEntry:
    return PointEntry(
        position=translate_point(obj.x, obj.y),
        name=obj.name,
        rotation=obj.rotation,
    )


def parse_rectangle(obj: TiledObject) -> RectangleEntry:
    return RectangleEntry(
        position=Point2D(x=obj.x, y=obj.y),
        width=obj.width,
        height=obj.height,
        name=obj.name,
        rotation=obj.rotation,
    )


def parse_polygon(obj: TiledObject) -> PolygonEntry:
    return PolygonEntry(
        vertices=[translate_point(obj.x, obj.y, v) for v in obj.polygon],
        closed=obj.closed,
        name=obj.name,
        rotation=obj.rotation,
    )


def collect_objects(layers: list[TiledLayer]) -> tuple[list[PointEntry], list[RectangleEntry], list[PolygonEntry]]:
    points: list[PointEntry] = []
    rectangles: list[RectangleEntry] = []
    polygons: list[PolygonEntry] = []

    for layer in layers:
        for obj in layer.objects:
            if obj.point:
                points.append(parse_point(obj))
                continue

            if obj.polygon:
                entry = parse_polygon(obj)
                if len(entry.vertices) >= 2:
                    polygons.append(entry)
                continue

            if obj.width != 0 or obj.height != 0:
                rectangles.append(parse_rectangle(obj))

    return points, rectangles, polygons


def collect_images(layers: list[TiledLayer]) -> list[ImageEntry]:
    images: list[ImageEntry] = []
    for layer in layers:
        if layer.type != "imagelayer":
            continue

        x = float(layer.offsetx if layer.offsetx is not None else layer.x)
        y = float(layer.offsety if layer.offsety is not None else layer.y)

        entry = ImageEntry(
            name=layer.name,
            image=layer.image,
            position=Point2D(x=x, y=y),
            width=layer.imagewidth or layer.width,
            height=layer.imageheight or layer.height,
        )

        for prop in layer.properties:
            if prop.name == "index":
                entry.index = prop.value
                break

        images.append(entry)
    return images


# ── Serialization ───────────────────────────────────────────────────────────────


def serialize(obj: Any) -> Any:
    """Recursively convert dataclasses to dicts, dropping None values."""
    if hasattr(obj, "__dataclass_fields__"):
        return {k: serialize(v) for k, v in obj.__dict__.items() if v is not None}
    if isinstance(obj, list):
        return [serialize(item) for item in obj]
    return obj


# ── Entry point ─────────────────────────────────────────────────────────────────


def export_layers(input_path: Path, output_path: Path) -> None:
    document = TiledDocument.from_raw(load_json(input_path))

    object_layers = [layer for layer in document.layers if layer.type == "objectgroup"]
    points, rectangles, polygons = collect_objects(object_layers)

    summary = LayerSummary(
        points=points,
        rectangles=rectangles,
        polygons=polygons,
        images=collect_images(document.layers),
    )

    output_path.parent.mkdir(parents=True, exist_ok=True)
    dump_json(serialize(summary), output_path)
    print(f"Wrote {output_path.name}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Produce a single JSON summary of object/image layers from Tiled."
    )
    parser.add_argument(
        "--input",
        type=Path,
        default=DEFAULT_INPUT,
        help="Path to Tiled export (default: tiled/objects.json)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="Output JSON file (default: resources/json/layers.json)",
    )
    return parser


def main() -> None:
    args = build_parser().parse_args()
    if not args.input.exists():
        raise SystemExit(f"Input file not found: {args.input}")
    export_layers(args.input, args.output)


if __name__ == "__main__":
    main()