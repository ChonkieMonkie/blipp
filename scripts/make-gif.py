#!/usr/bin/env python3
# Blipp, a menu bar sidekick that shows how your Mac is doing.
# Copyright (C) 2026  Anton Gedda
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

"""Turns a folder of frames from `Blipp --render-animations` into a GIF.

    python3 scripts/make-gif.py <frames folder> <out.gif> [--scale 0.5]

Needs Pillow. All frames share one palette, so colors don't shimmer from frame to frame,
and each frame only stores the part that changed. Fully transparent pixels (the rounded
corners) stay transparent.
"""

import argparse
import pathlib

from PIL import Image

TRANSPARENT = 255


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("frames", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--scale", type=float, default=1.0)
    args = parser.parse_args()

    paths = sorted(args.frames.glob("frame-*.png"))
    delays = [int(line) for line in (args.frames / "delays.txt").read_text().split()]
    frames = [Image.open(path).convert("RGBA") for path in paths]
    if args.scale != 1:
        size = (round(frames[0].width * args.scale), round(frames[0].height * args.scale))
        frames = [frame.resize(size, Image.LANCZOS) for frame in frames]

    # One palette for the whole animation, from a sample of frames side by side.
    sample = frames[:: max(1, len(frames) // 24)]
    sheet = Image.new("RGB", (sample[0].width, sample[0].height * len(sample)))
    for index, frame in enumerate(sample):
        sheet.paste(frame.convert("RGB"), (0, index * frame.height))
    palette = sheet.quantize(colors=TRANSPARENT, method=Image.Quantize.MEDIANCUT)

    output = []
    for frame in frames:
        indexed = frame.convert("RGB").quantize(palette=palette, dither=Image.Dither.NONE)
        mask = frame.getchannel("A").point(lambda alpha: 255 if alpha < 128 else 0)
        indexed.paste(TRANSPARENT, mask=mask)
        output.append(indexed)

    output[0].save(
        args.output,
        save_all=True,
        append_images=output[1:],
        duration=[delay * 10 for delay in delays[: len(output)]],
        loop=0,
        transparency=TRANSPARENT,
        disposal=1,
        optimize=False,
    )
    print(f"{args.output}: {len(output)} frames, {args.output.stat().st_size / 1_000_000:.1f} MB")


if __name__ == "__main__":
    main()
