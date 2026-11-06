"""Render a terminal-style demo GIF of claude-switch (output mirrors the real tool)."""

import sys
from PIL import Image, ImageDraw, ImageFont

OUT = sys.argv[1]
FONT = ImageFont.truetype(r"C:\Windows\Fonts\CascadiaMono.ttf", 17)
W, PAD, LINE_H, TITLE_H = 980, 22, 26, 34
ROWS = 15
H = TITLE_H + PAD * 2 + LINE_H * ROWS

BG, TITLE_BG = (24, 26, 33), (38, 41, 51)
FG, DIM = (220, 223, 228), (128, 134, 148)
PROMPT, CMD = (97, 175, 239), (229, 229, 229)
GREEN, YELLOW, MAGENTA = (152, 195, 121), (229, 192, 123), (198, 120, 221)

PS = "PS C:\\Users\\you> "

# Each line: list of (text, color) segments
def prompt(cmd_text):
    return [(PS, PROMPT), (cmd_text, CMD)]

LIST_BEFORE = [
    [("", FG)],
    [("* main         you@gmail.com  ", FG), ("[active, default, cursor]", GREEN)],
    [("  work         you@company.com", FG)],
    [("", FG)],
]
SWITCH_OUT = [
    [("Cursor Claude Code extension -> ", FG), ("work", YELLOW), (" (you@company.com)", FG)],
    [("In Cursor run 'Developer: Reload Window' (Ctrl+Shift+P) to apply.", DIM)],
]
LIST_AFTER = [
    [("", FG)],
    [("* main         you@gmail.com  ", FG), ("[active, default]", GREEN)],
    [("  work         you@company.com  ", FG), ("[cursor]", GREEN)],
    [("", FG)],
]
FOOTER = [("# Reload Window -> Claude Code in Cursor now runs as you@company.com. No re-login.", MAGENTA)]


def render(lines, cursor=False):
    img = Image.new("RGB", (W, H), BG)
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, W, TITLE_H], fill=TITLE_BG)
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        x = 18 + i * 22
        d.ellipse([x, 11, x + 12, 23], fill=c)
    title = "claude-switch: switch Claude Code accounts"
    tw = d.textlength(title, font=FONT)
    d.text(((W - tw) / 2, 7), title, font=FONT, fill=DIM)

    visible = lines[-ROWS:]
    for row, segs in enumerate(visible):
        x, y = PAD, TITLE_H + PAD + row * LINE_H
        for text, color in segs:
            d.text((x, y), text, font=FONT, fill=color)
            x += d.textlength(text, font=FONT)
        if cursor and row == len(visible) - 1:
            d.rectangle([x + 1, y + 3, x + 10, y + LINE_H - 4], fill=CMD)
    return img


frames, durations = [], []


def add(lines, ms, cursor=False):
    frames.append(render(lines, cursor))
    durations.append(ms)


def type_cmd(screen, cmd_text):
    for i in range(len(cmd_text) + 1):
        add(screen + [prompt(cmd_text[:i])], 70 if i else 500, cursor=True)
    add(screen + [prompt(cmd_text)], 450, cursor=True)
    return screen + [prompt(cmd_text)]


screen = []
screen = type_cmd(screen, "cs")
screen += LIST_BEFORE
add(screen + [prompt("")], 1600, cursor=True)

screen = type_cmd(screen, "cs cursor work")
screen += SWITCH_OUT + [[("", FG)]]
add(screen + [prompt("")], 2200, cursor=True)

screen = type_cmd(screen, "cs")
screen += LIST_AFTER
add(screen + [prompt("")], 1200, cursor=True)

screen += [FOOTER]
add(screen, 4000)

# Shared palette keeps the file small and colors stable across frames
palette = frames[-1].quantize(colors=32, method=Image.Quantize.MEDIANCUT)
pframes = [f.quantize(palette=palette, dither=Image.Dither.NONE) for f in frames]
pframes[0].save(
    OUT, save_all=True, append_images=pframes[1:], duration=durations, loop=0, optimize=True
)
frames[-1].save(OUT.replace(".gif", "-last.png"))
print(f"{len(frames)} frames, {sum(durations) / 1000:.1f}s")
