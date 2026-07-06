#!/usr/bin/env python3
from __future__ import annotations

import json
import math
from pathlib import Path
from typing import Iterable

from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
ASSET_ROOT = ROOT / "Sources/iOS/Assets.xcassets"
APPICON_ROOT = ASSET_ROOT / "AppIcon.appiconset"

SIZE = 1024


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def lerp_color(start: tuple[int, int, int], end: tuple[int, int, int], t: float) -> tuple[int, int, int]:
    return tuple(round(lerp(sa, ea, t)) for sa, ea in zip(start, end))


def draw_vertical_gradient(size: int, top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    image = Image.new("RGBA", (size, size))
    draw = ImageDraw.Draw(image)
    for y in range(size):
        color = lerp_color(top, bottom, y / (size - 1))
        draw.line((0, y, size, y), fill=(*color, 255))
    return image


def add_glow(base: Image.Image, box: tuple[int, int, int, int], color: tuple[int, int, int, int], blur: int) -> None:
    glow = Image.new("RGBA", base.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(box, fill=color)
    glow = glow.filter(ImageFilter.GaussianBlur(blur))
    base.alpha_composite(glow)


def rounded_top_mask(size: int, rect: tuple[int, int, int, int], radius: int, header_bottom: int) -> Image.Image:
    mask = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(mask)
    left, top, right, _ = rect
    draw.rounded_rectangle((left, top, right, header_bottom), radius=radius, fill=255)
    draw.rectangle((left, top + radius, right, header_bottom), fill=255)
    return mask


def make_background() -> Image.Image:
    base = draw_vertical_gradient(SIZE, (8, 11, 20), (20, 28, 48))

    add_glow(base, (120, 60, 900, 820), (40, 110, 255, 100), 120)
    add_glow(base, (220, 320, 860, 980), (0, 220, 255, 72), 140)

    vignette = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(vignette)
    for inset in range(0, 80, 4):
        alpha = round(lerp(0, 45, inset / 76))
        draw.rounded_rectangle(
            (inset, inset, SIZE - inset, SIZE - inset),
            radius=240 - inset,
            outline=(0, 0, 0, alpha),
            width=4,
        )
    base.alpha_composite(vignette)
    return base


def make_card_shadow() -> Image.Image:
    shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(shadow)
    draw.rounded_rectangle((192, 174, 832, 888), radius=152, fill=(0, 0, 0, 150))
    return shadow.filter(ImageFilter.GaussianBlur(38))


def fill_polygon_with_vertical_gradient(points: Iterable[tuple[int, int]], top: tuple[int, int, int], bottom: tuple[int, int, int]) -> Image.Image:
    gradient = draw_vertical_gradient(SIZE, top, bottom)
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).polygon(list(points), fill=255)
    result = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    result.paste(gradient, mask=mask)
    return result


def make_default_icon() -> Image.Image:
    base = make_background()
    base.alpha_composite(make_card_shadow())

    card_rect = (214, 158, 810, 858)
    header_bottom = 356
    radius = 150

    card = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle(card_rect, radius=radius, fill=(245, 247, 251, 255))

    header = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(header).rectangle((card_rect[0], card_rect[1], card_rect[2], header_bottom), fill=(255, 91, 87, 255))
    header = Image.composite(header, Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)), rounded_top_mask(SIZE, card_rect, radius, header_bottom))
    card.alpha_composite(header)

    draw = ImageDraw.Draw(card)
    draw.rounded_rectangle(card_rect, radius=radius, outline=(255, 255, 255, 64), width=4)
    draw.line((card_rect[0] + 44, header_bottom, card_rect[2] - 44, header_bottom), fill=(255, 255, 255, 78), width=4)

    for x in (374, 650):
        draw.rounded_rectangle((x - 26, 124, x + 26, 216), radius=26, fill=(188, 34, 45, 255))
        draw.ellipse((x - 12, 190, x + 12, 214), fill=(245, 247, 251, 255))

    line_fill = (198, 205, 216, 255)
    draw.rounded_rectangle((292, 438, 446, 472), radius=17, fill=line_fill)
    draw.rounded_rectangle((300, 518, 428, 552), radius=17, fill=line_fill)
    draw.rounded_rectangle((312, 598, 402, 632), radius=17, fill=line_fill)
    draw.rounded_rectangle((578, 438, 732, 472), radius=17, fill=line_fill)
    draw.rounded_rectangle((596, 518, 724, 552), radius=17, fill=line_fill)

    funnel_shadow = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    shadow_points = [(330, 418), (694, 418), (617, 564), (561, 650), (561, 750), (463, 750), (463, 650), (407, 564)]
    ImageDraw.Draw(funnel_shadow).polygon(shadow_points, fill=(0, 0, 0, 110))
    base.alpha_composite(funnel_shadow.filter(ImageFilter.GaussianBlur(26)))

    funnel_points = [(334, 412), (690, 412), (612, 556), (556, 642), (556, 748), (468, 748), (468, 642), (412, 556)]
    funnel = fill_polygon_with_vertical_gradient(funnel_points, (101, 236, 255), (54, 106, 255))
    base.alpha_composite(card)
    base.alpha_composite(funnel)

    highlight = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    highlight_points = [(392, 434), (542, 434), (500, 514), (470, 560), (470, 692), (432, 692), (432, 570), (452, 528)]
    ImageDraw.Draw(highlight).polygon(highlight_points, fill=(255, 255, 255, 76))
    base.alpha_composite(highlight.filter(ImageFilter.GaussianBlur(6)))

    draw = ImageDraw.Draw(base)
    draw.rounded_rectangle((446, 786, 578, 820), radius=17, fill=(118, 229, 255, 255))
    draw.rounded_rectangle((460, 838, 564, 860), radius=11, fill=(255, 255, 255, 66))

    sheen = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(sheen).polygon([(160, 0), (430, 0), (820, 1024), (540, 1024)], fill=(255, 255, 255, 20))
    base.alpha_composite(sheen.filter(ImageFilter.GaussianBlur(32)))
    return base


def make_dark_icon() -> Image.Image:
    icon = make_default_icon()
    tint = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(tint).rounded_rectangle((0, 0, SIZE, SIZE), radius=240, fill=(5, 7, 12, 46))
    icon.alpha_composite(tint)

    deep_blue = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    ImageDraw.Draw(deep_blue).ellipse((180, 160, 860, 860), fill=(36, 54, 100, 40))
    icon.alpha_composite(deep_blue.filter(ImageFilter.GaussianBlur(90)))
    return icon


def make_tinted_icon() -> Image.Image:
    icon = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(icon)

    draw.rounded_rectangle((214, 158, 810, 858), radius=150, outline=(255, 255, 255, 255), width=48)
    draw.line((258, 356, 766, 356), fill=(255, 255, 255, 255), width=42)

    for x in (374, 650):
        draw.rounded_rectangle((x - 26, 118, x + 26, 218), radius=26, fill=(255, 255, 255, 255))

    funnel_points = [(334, 412), (690, 412), (612, 556), (556, 642), (556, 748), (468, 748), (468, 642), (412, 556)]
    draw.polygon(funnel_points, fill=(255, 255, 255, 255))
    draw.rounded_rectangle((446, 786, 578, 820), radius=17, fill=(255, 255, 255, 255))

    return icon


def save_png(image: Image.Image, path: Path) -> None:
    image.save(path, format="PNG")


def write_contents_json() -> None:
    contents = {
        "images": [
            {
                "filename": "AppIcon-light.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
            {
                "appearances": [
                    {
                        "appearance": "luminosity",
                        "value": "dark",
                    }
                ],
                "filename": "AppIcon-dark.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
            {
                "appearances": [
                    {
                        "appearance": "luminosity",
                        "value": "tinted",
                    }
                ],
                "filename": "AppIcon-tinted.png",
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024",
            },
        ],
        "info": {
            "author": "xcode",
            "version": 1,
        },
    }
    (ASSET_ROOT / "Contents.json").write_text(json.dumps({"info": {"author": "xcode", "version": 1}}, indent=2) + "\n")
    (APPICON_ROOT / "Contents.json").write_text(json.dumps(contents, indent=2) + "\n")


def main() -> None:
    ASSET_ROOT.mkdir(parents=True, exist_ok=True)
    APPICON_ROOT.mkdir(parents=True, exist_ok=True)

    save_png(make_default_icon(), APPICON_ROOT / "AppIcon-light.png")
    save_png(make_dark_icon(), APPICON_ROOT / "AppIcon-dark.png")
    save_png(make_tinted_icon(), APPICON_ROOT / "AppIcon-tinted.png")
    write_contents_json()

    preview = Image.new("RGBA", (SIZE * 3 + 96, SIZE + 64), (15, 18, 28, 255))
    preview.alpha_composite(make_default_icon(), (32, 32))
    preview.alpha_composite(make_dark_icon(), (SIZE + 48, 32))
    preview.alpha_composite(Image.alpha_composite(Image.new("RGBA", (SIZE, SIZE), (23, 27, 38, 255)), make_tinted_icon()), (SIZE * 2 + 64, 32))
    save_png(preview, ROOT / "build" / "app-icon-preview.png")


if __name__ == "__main__":
    main()
