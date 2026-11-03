#!/usr/bin/env python3
"""Generate the fixed lesson-narration subtitle timing and 16x16 glyph ROM."""

from __future__ import annotations

import argparse
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


GLYPH_SIZE = 16
ASCII_BASELINE_Y = 14


CAPTIONS: dict[int, list[str]] = {
    0: [
        "第一部分认识自然景物请听五个英语单词",
        "forest",
        "river",
        "lake",
        "mountain",
        "hill",
        "Forest是森林river是河流lake是湖泊",
        "mountain是高山hill是小山观察右侧照片找一找这些景物",
    ],
    1: [
        "第二部分用There is和There are描述景物",
        "There is接单数There are接复数",
        "There is a river in the forest",
        "这句话表示森林里有一条河",
        "There are some trees near the lake",
        "这句话表示湖边有一些树注意一个景物用is多个景物用are",
    ],
    2: [
        "第三部分用Is there和Are there询问自然景物先听两个问答",
        "Is there a bridge over the river",
        "Yes there is",
        "Are there any houses near the river",
        "Yes there are",
        "Is there询问单个景物Are there询问多个景物听完后进入选择练习",
    ],
}

# Start time of each caption in 0.1-second units.  These boundaries match the
# checked-in LMV1/WAV package.  The audio block converts them to consumed PCM
# sample counts so SD-card prefetch never advances a subtitle early.
CUE_TENTHS: dict[int, list[int]] = {
    0: [0, 58, 75, 90, 106, 120, 138, 183],
    1: [0, 48, 87, 119, 157, 189],
    2: [0, 75, 103, 126, 157, 183],
}


def render_glyph(character: str, font: ImageFont.FreeTypeFont) -> int:
    image = Image.new("1", (GLYPH_SIZE, GLYPH_SIZE), 0)
    draw = ImageDraw.Draw(image)
    if character.isascii():
        # Latin glyphs must share one baseline.  Centering each character by
        # its own bounding box lifts descenders such as g/p/y and makes words
        # look vertically staggered.
        left, _, right, _ = draw.textbbox(
            (0, 0), character, font=font, anchor="ls"
        )
        x = (GLYPH_SIZE - (right - left)) // 2 - left
        draw.text(
            (x, ASCII_BASELINE_Y),
            character,
            font=font,
            fill=1,
            anchor="ls",
        )
    else:
        left, top, right, bottom = draw.textbbox((0, 0), character, font=font)
        x = (GLYPH_SIZE - (right - left)) // 2 - left
        y = (GLYPH_SIZE - (bottom - top)) // 2 - top
        draw.text((x, y), character, font=font, fill=1)
    value = 0
    for row in range(GLYPH_SIZE):
        for column in range(GLYPH_SIZE):
            value = (value << 1) | int(image.getpixel((column, row)) != 0)
    return value


def glyph_row_bounds(value: int) -> tuple[int, int]:
    rows = [
        row
        for row in range(GLYPH_SIZE)
        if (value >> ((GLYPH_SIZE - 1 - row) * GLYPH_SIZE)) & 0xFFFF
    ]
    if not rows:
        raise ValueError("rendered glyph is empty")
    return min(rows), max(rows)


def validate_latin_baseline(font: ImageFont.FreeTypeFont) -> None:
    regular_bottom = glyph_row_bounds(render_glyph("A", font))[1]
    descender_bottom = glyph_row_bounds(render_glyph("g", font))[1]
    if descender_bottom <= regular_bottom:
        raise ValueError("Latin descender does not extend below the common baseline")
    for character in "AFgjpqy":
        _, top, _, bottom = font.getbbox(character, anchor="ls")
        if ASCII_BASELINE_Y + top < 0 or ASCII_BASELINE_Y + bottom > GLYPH_SIZE:
            raise ValueError(f"Latin glyph is clipped: {character}")


def ordered_characters() -> list[str]:
    result: list[str] = []
    seen: set[str] = {" "}
    for clip in range(3):
        for caption in CAPTIONS[clip]:
            for character in caption:
                if character not in seen:
                    seen.add(character)
                    result.append(character)
    if len(result) > 255:
        raise ValueError(f"subtitle ROM needs {len(result)} non-space glyphs")
    return result


def bram_font(glyphs: list[int]) -> list[str]:
    """Pack original rows into three native 512x16 synchronous ROM banks."""
    if len(glyphs) > 96:
        raise ValueError("caption font exceeds three BRAM banks")
    glyphs = glyphs + [0] * (96 - len(glyphs))
    lines = [
        "// One pixel-clock read, aligned with the OSD region/column stage.",
        "module lesson_subtitle_font_bram (",
        "    input wire clk, input wire [7:0] char_code,",
        "    input wire [3:0] row_index, output reg [15:0] font_row",
        ");",
        "reg [1:0] bank;",
        "reg valid;",
        "always @(posedge clk) begin",
        "    bank <= char_code[6:5];",
        "    valid <= char_code < 8'd96;",
        "end",
        "wire [8:0] addr = {char_code[4:0], row_index};",
    ]
    for bank in range(3):
        lines.extend([
            f"wire [8:0] low_{bank}, high_{bank};",
            "EG_PHY_BRAM #(",
            '    .MODE("PDPW8K"), .DATA_WIDTH_A("18"), .DATA_WIDTH_B("18"),',
            '    .REGMODE_A("NOREG"), .REGMODE_B("NOREG"), .GSR("DISABLE"),',
            '    .CEAMUX("1"), .CEBMUX("1"), .OCEAMUX("1"), .OCEBMUX("1"),',
            '    .WEAMUX("0"), .WEBMUX("0"),',
            '    .CSA0("1"), .CSA1("1"), .CSA2("1"),',
            '    .CSB0("1"), .CSB1("1"), .CSB2("1"),',
        ])
        for slot in range(32):
            glyph = glyphs[bank * 32 + slot]
            packed = sum(((glyph >> (240 - row * 16)) & 0xFFFF) << (row * 16)
                         for row in range(16))
            comma = "," if slot < 31 else ""
            lines.append(f"    .INIT_{slot:02X}(256'h{packed:064X}){comma}")
        lines.extend([
            f") bank_{bank} (",
            "    .addra(13'd0), .addrb({addr, 4'b1111}), .dia(9'd0), .dib(9'd0),",
            "    .clka(clk), .clkb(clk), .cea(1'b1), .ceb(1'b1),",
            "    .ocea(1'b1), .oceb(1'b1), .wea(1'b0), .web(1'b0),",
            "    .csa(3'b111), .csb(3'b111), .rsta(1'b0), .rstb(1'b0),",
            f"    .doa(low_{bank}), .dob(high_{bank}));",
        ])
    lines.extend(["always @* begin", "    font_row = 16'd0;", "    if (valid) case (bank)"])
    for bank in range(3):
        lines.append(f"        2'd{bank}: font_row = {{high_{bank}[7:0], low_{bank}[7:0]}};")
    lines.extend(["        default: font_row = 16'd0;", "    endcase", "end", "endmodule", ""])
    return lines


def generate(font_path: Path) -> str:
    for clip in range(3):
        if len(CAPTIONS[clip]) != len(CUE_TENTHS[clip]):
            raise ValueError(f"clip {clip} caption/timing count mismatch")
        if CUE_TENTHS[clip][0] != 0:
            raise ValueError(f"clip {clip} must begin at zero")
        if CUE_TENTHS[clip] != sorted(set(CUE_TENTHS[clip])):
            raise ValueError(f"clip {clip} cue times must increase")
        if any(len(text) > 40 for text in CAPTIONS[clip]):
            raise ValueError(f"clip {clip} caption exceeds 40 columns")

    font = ImageFont.truetype(str(font_path), 16)
    validate_latin_baseline(font)
    characters = ordered_characters()
    codes = {character: index + 1 for index, character in enumerate(characters)}

    lines = [
        "`timescale 1ns/1ps",
        "",
        "// Generated by scripts/build_lesson_subtitle_rom.py.",
        "// Cue time follows consumed 16 kHz PCM samples, never SD prefetch.",
        "// ASCII glyphs share a fixed baseline; CJK glyphs stay box-centered.",
        "module lesson_subtitle_timing #(",
        "    parameter integer SAMPLES_PER_TENTH = 1600",
        ") (",
        "    input  wire [1:0]  clip_index,",
        "    input  wire [19:0] sample_count,",
        "    output reg  [4:0]  cue_index",
        ");",
        "always @* begin",
        "    cue_index = 5'd0;",
        "    case (clip_index)",
    ]
    for clip in range(3):
        lines.append(f"        2'd{clip}: begin")
        for cue in range(len(CUE_TENTHS[clip]) - 1, 0, -1):
            keyword = "if" if cue == len(CUE_TENTHS[clip]) - 1 else "else if"
            threshold = CUE_TENTHS[clip][cue]
            lines.append(
                f"            {keyword} (sample_count >= "
                f"({threshold} * SAMPLES_PER_TENTH)) cue_index = 5'd{cue};"
            )
        lines.append("        end")
    lines.extend(
        [
            "        default: cue_index = 5'd0;",
            "    endcase",
            "end",
            "endmodule",
            "",
            "module lesson_subtitle_rom (",
            "    input  wire [1:0] clip_index,",
            "    input  wire [4:0] cue_index,",
            "    input  wire [5:0] char_index,",
            "    input  wire [3:0] row_index,",
            "    output reg  [7:0] char_code,",
            "    output wire [15:0] font_row",
            ");",
            "lesson_subtitle_font u_font (.char_code(char_code), .row_index(row_index), .font_row(font_row));",
            "always @* begin",
            "    char_code = 8'd0;",
            "    case ({clip_index, cue_index})",
        ]
    )
    for clip in range(3):
        for cue, caption in enumerate(CAPTIONS[clip]):
            key = (clip << 5) | cue
            start = (40 - len(caption)) // 2
            caption_comment = caption.encode("unicode_escape").decode("ascii")
            lines.append(f"        7'd{key}: begin // {caption_comment}")
            lines.append("            case (char_index)")
            for offset, character in enumerate(caption):
                code = 0 if character == " " else codes[character]
                lines.append(
                    f"                6'd{start + offset}: char_code = 8'd{code};"
                )
            lines.append("                default: char_code = 8'd0;")
            lines.append("            endcase")
            lines.append("        end")
    lines.extend(
        [
            "        default: char_code = 8'd0;",
            "    endcase",
            "end",
            "endmodule",
            "",
            "// Dedicated caption code space, shared by direct and pipelined users.",
            "module lesson_subtitle_font (",
            "    input wire [7:0] char_code,",
            "    input wire [3:0] row_index,",
            "    output reg [15:0] font_row",
            ");",
            "reg [255:0] glyph;",
            "always @* begin",
            "    glyph = 256'd0;",
            "    case (char_code)",
        ]
    )
    for character in characters:
        value = render_glyph(character, font)
        comment = (
            character
            if character.isascii() and character.isprintable()
            else f"U+{ord(character):04X}"
        )
        lines.append(
            f"        8'd{codes[character]}: glyph = 256'h{value:064X}; // {comment}"
        )
    lines.extend(
        [
            "        default: glyph = 256'd0;",
            "    endcase",
            "",
            "    case (row_index)",
        ]
    )
    for row in range(15):
        high = 255 - row * 16
        low = high - 15
        lines.append(f"        4'd{row}: font_row = glyph[{high}:{low}];")
    lines.extend(
        [
            "        default: font_row = glyph[15:0];",
            "    endcase",
            "end",
            "endmodule",
            "",
        ]
    )
    lines.extend(bram_font([0] + [render_glyph(character, font) for character in characters]))
    return "\n".join(lines)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--font",
        type=Path,
        default=Path(r"C:\Windows\Fonts\simhei.ttf"),
    )
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    if not args.font.is_file():
        raise FileNotFoundError(args.font)
    source = generate(args.font)
    if args.output is None:
        print(source, end="")
    else:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(source, encoding="utf-8", newline="\n")
        print(f"BUILD_PASS lesson_subtitle_rom {args.output}")


if __name__ == "__main__":
    main()
