from __future__ import annotations

import io
import json
import struct
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
LOCAL_DEPS = ROOT / "tmp" / "python_svg_deps"
if LOCAL_DEPS.exists():
    sys.path.insert(0, str(LOCAL_DEPS))

import cairosvg  # type: ignore  # noqa: E402
from PIL import Image, ImageDraw, ImageFont  # type: ignore  # noqa: E402


WIDTH = 1536
HEIGHT = 1152
CARD_SIZES = [(320, 240), (640, 480), (960, 720), (1280, 960)]

INK = "#263238"
SLATE = "#455A64"
CORAL = "#FF725E"
CORAL_DARK = "#D95A48"
CREAM = "#F7F4EE"
WHITE = "#FFFFFF"
MIST = "#EDF1F2"
MINT = "#DDEFE8"
GOLD = "#F5C85B"
BLUE = "#6EA8D9"

REGULAR_FONT = Path(r"C:\Windows\Fonts\segoeui.ttf")
BOLD_FONT = Path(r"C:\Windows\Fonts\seguisb.ttf")

VECTOR_DIR = ROOT / "artifacts" / "english_task_map" / "source_vectors"
OUTPUT_ROOT = ROOT / "artifacts" / "pep_english_cards"
SOURCE_DIR = OUTPUT_ROOT / "source"
TF_DIR = OUTPUT_ROOT / "tf_card_ready"
PREVIEW_DIR = OUTPUT_ROOT / "preview"


CARDS = [
    {
        "number": 1,
        "unit": "UNIT 1",
        "title": "MY CLASSROOM",
        "instruction": "LOOK AND CHOOSE",
        "question": "Where is the picture?",
        "options": [
            "It is on the desk.",
            "It is near the window.",
            "It is under the chair.",
            "It is in the schoolbag.",
        ],
        "answer": "B",
        "answer_code": 1,
        "prompt_token": "0x10",
        "option_tokens": ["0x11", "0x12", "0x13", "0x14"],
        "word_bank": ["window", "picture", "blackboard", "desk"],
        "vector": "01_classroom_storyset_pana.svg",
        "source_page": "https://storyset.com/illustration/classroom/pana",
        "source_url": "https://stories.freepiklabs.com/storage/12173/Classroom-%281%29-01.svg",
        "filename": "01_my_classroom",
    },
    {
        "number": 2,
        "unit": "UNIT 2",
        "title": "MY SCHOOLBAG",
        "instruction": "COUNT AND CHOOSE",
        "question": "How many storybooks are in the schoolbag?",
        "options": ["One.", "Two.", "Three.", "Four."],
        "answer": "C",
        "answer_code": 2,
        "prompt_token": "0x20",
        "option_tokens": ["0x21", "0x22", "0x23", "0x24"],
        "word_bank": ["schoolbag", "storybook", "English book", "maths book"],
        "vector": "02_schoolbag_storyset_pana.svg",
        "source_page": "https://storyset.com/illustration/children-preparing-their-backpack/pana",
        "source_url": "https://stories.freepiklabs.com/storage/15779/Children-preparing-their-backpack-01.svg",
        "filename": "02_my_schoolbag",
    },
    {
        "number": 3,
        "unit": "UNIT 4",
        "title": "MY HOME",
        "instruction": "LOOK AND CHOOSE",
        "question": "Where are the keys?",
        "options": [
            "They are on the table.",
            "They are in the door.",
            "They are under the sofa.",
            "They are near the phone.",
        ],
        "answer": "B",
        "answer_code": 1,
        "prompt_token": "0x30",
        "option_tokens": ["0x31", "0x32", "0x33", "0x34"],
        "word_bank": ["living room", "door", "keys", "sofa"],
        "vector": "03_my_home_storyset_pana.svg",
        "source_page": "https://storyset.com/illustration/living-room/pana",
        "source_url": "https://stories.freepiklabs.com/storage/47382/Living-room-01.svg",
        "filename": "03_my_home",
    },
    {
        "number": 4,
        "unit": "UNIT 5",
        "title": "DINNER'S READY",
        "instruction": "LOOK AND CHOOSE",
        "question": "What would you like?",
        "options": [
            "Some rice and fish.",
            "Some noodles and vegetables.",
            "Some soup and bread.",
            "Some beef and chicken.",
        ],
        "answer": "B",
        "answer_code": 1,
        "prompt_token": "0x40",
        "option_tokens": ["0x41", "0x42", "0x43", "0x44"],
        "word_bank": ["noodles", "vegetables", "bowl", "chopsticks"],
        "vector": "04_dinner_storyset_pana.svg",
        "source_page": "https://storyset.com/illustration/eating-together/pana",
        "source_url": "https://stories.freepiklabs.com/storage/1770/Eating-together-01.svg",
        "filename": "04_dinners_ready",
    },
]


def font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    path = BOLD_FONT if bold else REGULAR_FONT
    if not path.exists():
        raise FileNotFoundError(f"Required font is missing: {path}")
    return ImageFont.truetype(str(path), size=size)


def render_svg(path: Path, width: int = 920, height: int = 690) -> Image.Image:
    if not path.exists():
        raise FileNotFoundError(f"Source vector is missing: {path}")
    png = cairosvg.svg2png(
        url=str(path), output_width=width, output_height=height
    )
    return Image.open(io.BytesIO(png)).convert("RGBA")


def fit_text_font(draw: ImageDraw.ImageDraw, text: str, max_width: int,
                  start_size: int, min_size: int, bold: bool = False):
    for size in range(start_size, min_size - 1, -1):
        candidate = font(size, bold=bold)
        if draw.textbbox((0, 0), text, font=candidate)[2] <= max_width:
            return candidate
    return font(min_size, bold=bold)


def paste_contain(canvas: Image.Image, art: Image.Image, box: tuple[int, int, int, int]):
    x0, y0, x1, y1 = box
    max_w = x1 - x0
    max_h = y1 - y0
    scale = min(max_w / art.width, max_h / art.height)
    size = (round(art.width * scale), round(art.height * scale))
    resized = art.resize(size, Image.Resampling.LANCZOS)
    x = x0 + (max_w - size[0]) // 2
    y = y0 + (max_h - size[1]) // 2
    canvas.alpha_composite(resized, (x, y))


def draw_header(draw: ImageDraw.ImageDraw, card: dict):
    draw.rectangle((0, 0, WIDTH, 126), fill=INK)
    draw.rounded_rectangle((50, 32, 198, 94), radius=28, fill=CORAL)
    draw.text((124, 63), card["unit"], font=font(30, True), fill=WHITE, anchor="mm")
    draw.text((230, 64), card["title"], font=font(50, True), fill=WHITE, anchor="lm")
    draw.text((1478, 64), f'{card["number"]}/4', font=font(30, True), fill=MIST, anchor="rm")


def draw_question_panel(draw: ImageDraw.ImageDraw, card: dict):
    x0, y0, x1, y1 = 956, 158, 1488, 1064
    draw.rounded_rectangle((x0, y0, x1, y1), radius=34, fill=WHITE, outline="#D9E0E2", width=3)
    draw.rounded_rectangle((x0 + 34, y0 + 34, x0 + 316, y0 + 84), radius=22, fill=MINT)
    draw.text((x0 + 175, y0 + 59), card["instruction"], font=font(24, True), fill=SLATE, anchor="mm")

    question_font = fit_text_font(draw, card["question"], 460, 47, 34, True)
    question_box = draw.textbbox((0, 0), card["question"], font=question_font)
    if question_box[2] <= 460:
        draw.text((x0 + 36, y0 + 124), card["question"], font=question_font, fill=INK)
        option_y = y0 + 232
    else:
        words = card["question"].split()
        split_at = max(1, len(words) // 2)
        line1 = " ".join(words[:split_at])
        line2 = " ".join(words[split_at:])
        draw.text((x0 + 36, y0 + 112), line1, font=font(39, True), fill=INK)
        draw.text((x0 + 36, y0 + 164), line2, font=font(39, True), fill=INK)
        option_y = y0 + 270

    option_h = 116
    option_gap = 24
    option_letters = "ABCD"
    for index, option in enumerate(card["options"]):
        top = option_y + index * (option_h + option_gap)
        draw.rounded_rectangle(
            (x0 + 34, top, x1 - 34, top + option_h),
            radius=24,
            fill="#F8FAFA",
            outline="#D7DFE1",
            width=3,
        )
        draw.ellipse((x0 + 52, top + 24, x0 + 120, top + 92), fill=CORAL)
        draw.text((x0 + 86, top + 58), option_letters[index], font=font(32, True), fill=WHITE, anchor="mm")
        option_font = fit_text_font(draw, option, 342, 31, 23)
        draw.text((x0 + 142, top + 58), option, font=option_font, fill=INK, anchor="lm")

    draw.text((x0 + 36, y1 - 48), "Choose A, B, C or D", font=font(22), fill=SLATE)


def draw_word_bank(draw: ImageDraw.ImageDraw, words: list[str]):
    draw.rounded_rectangle((74, 952, 916, 1036), radius=26, fill=INK)
    draw.text((102, 994), "WORD BANK", font=font(22, True), fill=GOLD, anchor="lm")
    text = "   •   ".join(words)
    word_font = fit_text_font(draw, text, 620, 25, 19)
    draw.text((278, 994), text, font=word_font, fill=WHITE, anchor="lm")


def draw_window_and_picture(draw: ImageDraw.ImageDraw):
    # A clear window and a separate framed picture immediately beside it.
    draw.rounded_rectangle((92, 192, 324, 422), radius=12, fill="#CDEAF7", outline=SLATE, width=8)
    draw.line((208, 198, 208, 416), fill=WHITE, width=8)
    draw.line((98, 306, 318, 306), fill=WHITE, width=8)
    draw.ellipse((124, 226, 168, 270), fill=GOLD)
    draw.polygon([(100, 390), (170, 318), (230, 390)], fill="#8BC69D")
    draw.polygon([(180, 390), (252, 330), (316, 390)], fill="#65A98A")

    draw.rounded_rectangle((346, 236, 520, 374), radius=10, fill=WHITE, outline=CORAL_DARK, width=10)
    draw.rectangle((366, 256, 500, 354), fill="#FFF2D0")
    draw.ellipse((386, 278, 426, 318), fill=GOLD)
    draw.polygon([(372, 342), (418, 302), (454, 342)], fill="#6EAD8D")
    draw.polygon([(420, 342), (464, 312), (496, 342)], fill=BLUE)


def draw_storybook_inset(draw: ImageDraw.ImageDraw):
    draw.ellipse((500, 548, 884, 920), fill=WHITE, outline=CORAL, width=10)
    draw.rounded_rectangle((590, 716, 802, 848), radius=35, fill=CORAL, outline=CORAL_DARK, width=6)
    draw.arc((590, 660, 802, 770), start=180, end=360, fill=CORAL_DARK, width=10)
    book_colors = [BLUE, GOLD, "#77B99A"]
    x_positions = [620, 682, 744]
    for index, (x, colour) in enumerate(zip(x_positions, book_colors), start=1):
        draw.rounded_rectangle((x, 604, x + 52, 760), radius=8, fill=colour, outline=INK, width=4)
        draw.text((x + 26, 654), "STORY", font=font(13, True), fill=INK, anchor="mm")
        draw.text((x + 26, 684), str(index), font=font(20, True), fill=INK, anchor="mm")
    draw.text((692, 874), "storybooks", font=font(25, True), fill=INK, anchor="mm")


def draw_door_and_keys(draw: ImageDraw.ImageDraw):
    draw.rounded_rectangle((82, 218, 316, 842), radius=12, fill="#D3A477", outline=INK, width=8)
    draw.rectangle((118, 264, 280, 480), fill="#E6C19A", outline="#A87850", width=5)
    draw.rectangle((118, 524, 280, 786), fill="#E6C19A", outline="#A87850", width=5)
    draw.ellipse((263, 498, 293, 528), fill=GOLD, outline=INK, width=4)
    draw.line((291, 514, 344, 552), fill=INK, width=8)
    draw.ellipse((332, 540, 370, 578), outline=CORAL, width=8)
    draw.ellipse((354, 558, 388, 592), outline=CORAL, width=8)
    draw.text((198, 818), "door", font=font(24, True), fill=INK, anchor="mm")


def draw_food_foreground(draw: ImageDraw.ImageDraw):
    # Noodles and vegetables are the only foreground meal pair.
    draw.rounded_rectangle((128, 700, 844, 904), radius=50, fill="#F0D2A4", outline=CORAL_DARK, width=6)
    draw.ellipse((184, 730, 484, 888), fill=WHITE, outline=SLATE, width=5)
    draw.ellipse((212, 754, 456, 854), fill="#F5D57A", outline=GOLD, width=4)
    for offset in range(0, 190, 24):
        draw.arc((224 + offset // 3, 764, 430 - offset // 4, 844), start=10, end=170, fill="#D99D35", width=4)
    draw.line((448, 720, 510, 888), fill=INK, width=7)
    draw.line((468, 720, 530, 888), fill=INK, width=7)

    draw.ellipse((548, 738, 808, 876), fill=WHITE, outline=SLATE, width=5)
    vegetables = [
        (584, 784, 638, 838, "#70B77E"),
        (624, 760, 682, 822, "#F2B84B"),
        (670, 788, 728, 846, "#7EBE6A"),
        (716, 758, 774, 820, CORAL),
    ]
    for x0, y0, x1, y1, colour in vegetables:
        draw.ellipse((x0, y0, x1, y1), fill=colour, outline=INK, width=3)
    draw.text((334, 884), "noodles", font=font(22, True), fill=INK, anchor="mm")
    draw.text((680, 884), "vegetables", font=font(22, True), fill=INK, anchor="mm")


def build_card(card: dict) -> Image.Image:
    canvas = Image.new("RGBA", (WIDTH, HEIGHT), CREAM)
    draw = ImageDraw.Draw(canvas)
    draw_header(draw, card)
    draw.rounded_rectangle((48, 158, 932, 1064), radius=34, fill=WHITE, outline="#D9E0E2", width=3)

    art = render_svg(VECTOR_DIR / card["vector"])
    if card["number"] == 1:
        paste_contain(canvas, art, (80, 296, 912, 920))
        draw_window_and_picture(draw)
    elif card["number"] == 2:
        paste_contain(canvas, art, (94, 188, 832, 742))
        draw_storybook_inset(draw)
    elif card["number"] == 3:
        paste_contain(canvas, art, (242, 230, 918, 880))
        draw_door_and_keys(draw)
    else:
        paste_contain(canvas, art, (92, 190, 902, 796))
        draw_food_foreground(draw)

    draw_word_bank(draw, card["word_bank"])
    draw_question_panel(draw, card)
    draw.text((50, 1118), "PEP English • Grade 4A", font=font(19, True), fill=SLATE, anchor="lm")
    draw.text((1486, 1118), "Illustrations by Storyset / Freepik", font=font(18), fill=SLATE, anchor="rm")
    return canvas.convert("RGB")


def validate_bmp(path: Path, expected_size: tuple[int, int]):
    data = path.read_bytes()
    if data[:2] != b"BM":
        raise ValueError(f"Not a BMP file: {path}")
    width, height = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    compression = struct.unpack_from("<I", data, 30)[0]
    if (width, height) != expected_size or height <= 0 or bpp != 24 or compression != 0:
        raise ValueError(
            f"Invalid BMP {path}: {width}x{height}, bpp={bpp}, compression={compression}"
        )


def write_metadata():
    metadata = {
        "curriculum": "PEP English (starting from Grade 3), Grade 4A",
        "answer_encoding": {"A": 0, "B": 1, "C": 2, "D": 3},
        "answer_sequence": [card["answer"] for card in CARDS],
        "cards": CARDS,
        "attribution": "Illustrations by Storyset / Freepik",
        "license": "Freepik License; attribution required for free use. See each source page.",
    }
    (OUTPUT_ROOT / "questions.json").write_text(
        json.dumps(metadata, indent=2, ensure_ascii=False), encoding="utf-8"
    )

    lines = [
        "PEP English Grade 4A - Four-card exercise set",
        "",
        "Answer sequence: B / C / B / B",
        "",
    ]
    for card in CARDS:
        lines.extend([
            f'{card["unit"]} {card["title"]}',
            card["question"],
            *[f'{letter}. {option}' for letter, option in zip("ABCD", card["options"])],
            f'Answer: {card["answer"]}',
            "",
        ])
    lines.extend([
        "Attribution: Illustrations by Storyset / Freepik",
        "Source pages:",
        *[f'- {card["source_page"]}' for card in CARDS],
        "",
    ])
    (OUTPUT_ROOT / "questions_and_sources.txt").write_text(
        "\n".join(lines), encoding="utf-8"
    )


def build_contact_sheet(cards: list[Image.Image]):
    thumb_w, thumb_h = 768, 576
    sheet = Image.new("RGB", (thumb_w * 2, thumb_h * 2), "#DCE2E4")
    for index, card in enumerate(cards):
        thumb = card.resize((thumb_w, thumb_h), Image.Resampling.LANCZOS)
        sheet.paste(thumb, ((index % 2) * thumb_w, (index // 2) * thumb_h))
    sheet.save(PREVIEW_DIR / "pep_grade4a_contact_sheet.png", format="PNG", optimize=True)


def main():
    for directory in (SOURCE_DIR, TF_DIR, PREVIEW_DIR):
        directory.mkdir(parents=True, exist_ok=True)

    rendered_cards = []
    for card, size in zip(CARDS, CARD_SIZES):
        image = build_card(card)
        rendered_cards.append(image)
        source_path = SOURCE_DIR / f'{card["filename"]}.png'
        image.save(source_path, format="PNG", optimize=True)

        tf_image = image.resize(size, Image.Resampling.LANCZOS)
        bmp_path = TF_DIR / f'{card["number"]:02d}.bmp'
        tf_image.save(bmp_path, format="BMP")
        validate_bmp(bmp_path, size)

    build_contact_sheet(rendered_cards)
    write_metadata()
    print("BUILD_PASS pep_english_cards")
    print("Answer sequence: B/C/B/B")
    for card, size in zip(CARDS, CARD_SIZES):
        print(f'{card["number"]}: {card["unit"]} {card["title"]} -> {size[0]}x{size[1]} BMP')


if __name__ == "__main__":
    main()
