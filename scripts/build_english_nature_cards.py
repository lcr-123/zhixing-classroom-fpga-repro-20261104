from __future__ import annotations

import json
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = ROOT / "artifacts" / "english_nature_cards_v1"
MATERIAL_DIR = OUTPUT_ROOT / "materials"
SOURCE_DIR = OUTPUT_ROOT / "source_png"
PREVIEW_DIR = OUTPUT_ROOT / "preview"

WIDTH = 1280
HEIGHT = 960
DISPLAY_SIZE = (640, 480)

FONT_CN_REGULAR = Path(r"C:\Windows\Fonts\msyh.ttc")
FONT_CN_BOLD = Path(r"C:\Windows\Fonts\msyhbd.ttc")
FONT_EN_REGULAR = Path(r"C:\Windows\Fonts\arial.ttf")
FONT_EN_BOLD = Path(r"C:\Windows\Fonts\arialbd.ttf")

PAPER = "#F5F2EA"
WHITE = "#FFFDF9"
INK = "#172033"
MUTED = "#667085"
ACCENT = "#2F6B55"
ACCENT_BLUE = "#326A82"
SOFT = "#E5EFE8"
SOFT_BLUE = "#E5EFF3"
LINE = "#DED8CE"


CARDS = [
    {
        "number": 1,
        "kind": "学习",
        "title": "Nature Words",
        "label": "词汇学习",
        "photo": "nature_words.jpg",
        "accent": ACCENT,
        "soft": SOFT,
        "focus": (0.52, 0.50),
    },
    {
        "number": 2,
        "kind": "学习",
        "title": "Describe the Park",
        "label": "句型学习",
        "photo": "forest_river_natural.jpg",
        "accent": ACCENT_BLUE,
        "soft": SOFT_BLUE,
        "focus": (0.50, 0.55),
    },
    {
        "number": 3,
        "kind": "学习",
        "title": "Ask About Nature",
        "label": "情景问答",
        "photo": "bridge_village_natural.jpg",
        "accent": ACCENT,
        "soft": SOFT,
        "focus": (0.53, 0.56),
    },
    {
        "number": 4,
        "kind": "练习",
        "title": "Nature Challenge",
        "label": "词汇选择",
        "photo": "nature_words.jpg",
        "accent": ACCENT,
        "soft": SOFT,
        "focus": (0.52, 0.50),
        "answer": "C",
        "pool_group": "vocabulary",
        "question": "What is the large body of water?",
        "question_cn": "图中较大的一片水域是什么？",
        "options": ["forest", "river", "lake", "hill"],
    },
    {
        "number": 5,
        "kind": "练习",
        "title": "Word Challenge",
        "label": "词汇选择",
        "photo": "nature_words.jpg",
        "accent": ACCENT,
        "soft": SOFT,
        "focus": (0.52, 0.50),
        "answer": "B",
        "pool_group": "vocabulary",
        "question": "Which word means 森林?",
        "question_cn": "选择与中文意思相符的单词。",
        "options": ["river", "forest", "lake", "hill"],
    },
    {
        "number": 6,
        "kind": "练习",
        "title": "Word Challenge",
        "label": "词汇选择",
        "photo": "forest_river_natural.jpg",
        "accent": ACCENT,
        "soft": SOFT,
        "focus": (0.50, 0.55),
        "answer": "D",
        "pool_group": "vocabulary",
        "question": "Which word means 高山?",
        "question_cn": "选择与中文意思相符的单词。",
        "options": ["river", "hill", "lake", "mountain"],
    },
    {
        "number": 7,
        "kind": "练习",
        "title": "Sentence Challenge",
        "label": "句型选择",
        "photo": "forest_river_natural.jpg",
        "accent": ACCENT_BLUE,
        "soft": SOFT_BLUE,
        "focus": (0.50, 0.55),
        "answer": "B",
        "pool_group": "sentence",
        "question": "Which sentence is correct?",
        "question_cn": "请选择正确的句子。",
        "options": [
            "There are a river.",
            "There is a river in the forest.",
            "There is some trees.",
            "There are a lake.",
        ],
    },
    {
        "number": 8,
        "kind": "练习",
        "title": "Picture Challenge",
        "label": "看图选择",
        "photo": "bridge_village_natural.jpg",
        "accent": ACCENT,
        "soft": SOFT,
        "focus": (0.53, 0.56),
        "answer": "A",
        "pool_group": "sentence",
        "question": "Which sentence matches the picture?",
        "question_cn": "哪句话与右图相符？",
        "options": [
            "There are houses near the river.",
            "There is a classroom near the river.",
            "There are desks near the river.",
            "There is a blackboard near the river.",
        ],
    },
    {
        "number": 9,
        "kind": "练习",
        "title": "Grammar Challenge",
        "label": "语法选择",
        "photo": "nature_words.jpg",
        "accent": ACCENT_BLUE,
        "soft": SOFT_BLUE,
        "focus": (0.52, 0.50),
        "answer": "C",
        "pool_group": "sentence",
        "question": "Which sentence is correct?",
        "question_cn": "请选择正确的句子。",
        "options": [
            "There is some trees near the lake.",
            "There are a mountain.",
            "There are some trees near the lake.",
            "There is any houses.",
        ],
    },
    {
        "number": 10,
        "kind": "练习",
        "title": "Question Challenge",
        "label": "情景选择",
        "photo": "bridge_village_natural.jpg",
        "accent": ACCENT,
        "soft": SOFT,
        "focus": (0.53, 0.56),
        "answer": "A",
        "pool_group": "question",
        "question": "Is there a bridge over the river?",
        "question_cn": "根据右图选择合适的回答。",
        "options": ["Yes, there is.", "No, there isn't.", "Yes, there are.", "No, there aren't."],
    },
    {
        "number": 11,
        "kind": "练习",
        "title": "Question Challenge",
        "label": "情景选择",
        "photo": "bridge_village_natural.jpg",
        "accent": ACCENT_BLUE,
        "soft": SOFT_BLUE,
        "focus": (0.53, 0.56),
        "answer": "C",
        "pool_group": "question",
        "question": "Are there any houses near the river?",
        "question_cn": "根据右图选择合适的回答。",
        "options": ["Yes, there is.", "No, there isn't.", "Yes, there are.", "No, there aren't."],
    },
    {
        "number": 12,
        "kind": "练习",
        "title": "Question Challenge",
        "label": "情景选择",
        "photo": "nature_words.jpg",
        "accent": ACCENT,
        "soft": SOFT,
        "focus": (0.52, 0.50),
        "answer": "D",
        "pool_group": "question",
        "question": "Is there a classroom in the park?",
        "question_cn": "根据右图选择合适的回答。",
        "options": ["Yes, there are.", "No, there aren't.", "Yes, there is.", "No, there isn't."],
    },
]


SOURCES = [
    {
        "file": "nature_words.jpg",
        "source_page": "https://www.pexels.com/photo/mountain-and-river-landscape-11570735/",
        "use": "自然景观词汇学习与练习",
    },
    {
        "file": "forest_river_natural.jpg",
        "source_page": "https://www.pexels.com/photo/mountain-landscape-with-stream-27082654/",
        "use": "There is / There are 句型学习与练习",
    },
    {
        "file": "bridge_village_natural.jpg",
        "source_page": "https://www.pexels.com/photo/charming-riverside-village-with-stone-bridge-36686469/",
        "use": "Is there / Are there 情景问答与练习",
    },
]


def font(size: int, *, bold: bool = False, chinese: bool = False) -> ImageFont.FreeTypeFont:
    if chinese:
        path = FONT_CN_BOLD if bold else FONT_CN_REGULAR
    else:
        path = FONT_EN_BOLD if bold else FONT_EN_REGULAR
    if not path.exists():
        raise FileNotFoundError(f"缺少字体: {path}")
    return ImageFont.truetype(str(path), size=size)


def cover_crop(
    image: Image.Image,
    size: tuple[int, int],
    focus_x: float,
    focus_y: float,
) -> Image.Image:
    target_w, target_h = size
    source = image.convert("RGB")
    scale = max(target_w / source.width, target_h / source.height)
    resized = source.resize(
        (round(source.width * scale), round(source.height * scale)),
        Image.Resampling.LANCZOS,
    )
    max_left = max(0, resized.width - target_w)
    max_top = max(0, resized.height - target_h)
    left = round(max_left * min(1.0, max(0.0, focus_x)))
    top = round(max_top * min(1.0, max(0.0, focus_y)))
    return resized.crop((left, top, left + target_w, top + target_h))


def rounded_photo(
    canvas: Image.Image,
    image: Image.Image,
    box: tuple[int, int, int, int],
    focus: tuple[float, float],
) -> None:
    x0, y0, x1, y1 = box
    photo = cover_crop(image, (x1 - x0, y1 - y0), focus[0], focus[1])
    photo = ImageEnhance.Contrast(photo).enhance(0.98)
    mask = Image.new("L", photo.size, 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(
        (0, 0, photo.width - 1, photo.height - 1), radius=34, fill=255
    )
    canvas.paste(photo, (x0, y0), mask)


def draw_header(draw: ImageDraw.ImageDraw, card: dict) -> None:
    accent = card["accent"]
    draw.rounded_rectangle((44, 34, 198, 92), radius=28, fill=accent)
    draw.text(
        (121, 63),
        f'英语{card["kind"]}',
        font=font(27, bold=True, chinese=True),
        fill="white",
        anchor="mm",
    )
    draw.text(
        (226, 64),
        card["title"],
        font=font(42, bold=True),
        fill=INK,
        anchor="lm",
    )


def draw_label(draw: ImageDraw.ImageDraw, text: str, accent: str) -> None:
    label_font = font(20, bold=True, chinese=True)
    bbox = draw.textbbox((0, 0), text, font=label_font)
    width = bbox[2] - bbox[0] + 36
    draw.rounded_rectangle((76, 182, 76 + width, 226), radius=22, fill=accent)
    draw.text(
        (76 + width // 2, 204), text, font=label_font, fill="white", anchor="mm"
    )


def draw_operation_hint(
    draw: ImageDraw.ImageDraw,
    text: str,
    soft: str,
    accent: str,
    y0: int = 756,
) -> None:
    draw.rounded_rectangle((78, y0, 632, y0 + 86), radius=22, fill=soft)
    draw.text(
        (104, y0 + 27),
        "操作提示",
        font=font(20, bold=True, chinese=True),
        fill=accent,
        anchor="lm",
    )
    draw.text(
        (104, y0 + 61),
        text,
        font=font(19, chinese=True),
        fill=INK,
        anchor="lm",
    )


def draw_learning_words(draw: ImageDraw.ImageDraw, card: dict) -> None:
    words = [
        ("forest", "森林"),
        ("river", "河流"),
        ("lake", "湖泊"),
        ("mountain", "高山"),
        ("hill", "小山"),
    ]
    y = 270
    for english, chinese in words:
        draw.text((104, y), english, font=font(33, bold=True), fill=card["accent"], anchor="lm")
        draw.text((590, y), chinese, font=font(25, chinese=True), fill=INK, anchor="rm")
        draw.line((104, y + 34, 590, y + 34), fill=LINE, width=2)
        y += 82
    draw_operation_hint(draw, "播放讲解时，可切换内容或调节音量", card["soft"], card["accent"])


def draw_learning_sentence(draw: ImageDraw.ImageDraw, card: dict) -> None:
    draw.text((92, 274), "There is + 单数", font=font(31, bold=True, chinese=True), fill=card["accent"], anchor="lm")
    draw.text((92, 326), "某处有一个……", font=font(23, chinese=True), fill=MUTED, anchor="lm")
    draw.rounded_rectangle((82, 364, 628, 466), radius=20, fill=card["soft"])
    draw.text((108, 400), "There is a river", font=font(29, bold=True), fill=INK, anchor="lm")
    draw.text((108, 438), "in the forest.", font=font(29), fill=INK, anchor="lm")

    draw.text((92, 524), "There are + 复数", font=font(31, bold=True, chinese=True), fill=card["accent"], anchor="lm")
    draw.text((92, 576), "某处有一些……", font=font(23, chinese=True), fill=MUTED, anchor="lm")
    draw.rounded_rectangle((82, 614, 628, 716), radius=20, fill=card["soft"])
    draw.text((108, 650), "There are some trees", font=font(28, bold=True), fill=INK, anchor="lm")
    draw.text((108, 688), "near the lake.", font=font(28), fill=INK, anchor="lm")
    draw_operation_hint(draw, "听句子，观察单数与复数的变化", card["soft"], card["accent"], y0=766)


def draw_learning_question(draw: ImageDraw.ImageDraw, card: dict) -> None:
    blocks = [
        (
            "Is there a bridge over the river?",
            "Yes, there is.",
        ),
        (
            "Are there any houses near the river?",
            "Yes, there are.",
        ),
    ]
    y = 270
    for question, answer in blocks:
        draw.text((92, y), question, font=font(25, bold=True), fill=INK, anchor="lm")
        draw.text((92, y + 48), "这里有……吗？", font=font(21, chinese=True), fill=MUTED, anchor="lm")
        draw.rounded_rectangle((82, y + 84, 628, y + 154), radius=18, fill=card["soft"])
        draw.text((108, y + 119), answer, font=font(29, bold=True), fill=card["accent"], anchor="lm")
        y += 220
    draw_operation_hint(draw, "听完问答后，进入选择练习", card["soft"], card["accent"])


def draw_option(
    draw: ImageDraw.ImageDraw,
    y: int,
    letter: str,
    text: str,
    accent: str,
    *,
    size: int = 25,
) -> None:
    draw.rounded_rectangle((78, y, 632, y + 72), radius=18, fill="#FAFAF8", outline=LINE, width=2)
    draw.ellipse((94, y + 10, 146, y + 62), fill=accent)
    draw.text((120, y + 36), letter, font=font(23, bold=True), fill="white", anchor="mm")
    draw.text((170, y + 36), text, font=font(size, bold=True), fill=INK, anchor="lm")


def draw_exercise_words(draw: ImageDraw.ImageDraw, card: dict) -> None:
    draw.text((82, 272), "What is the large body of water?", font=font(27, bold=True), fill=INK, anchor="lm")
    draw.text((82, 315), "图中较大的一片水域是什么？", font=font(22, chinese=True), fill=MUTED, anchor="lm")
    for y, (letter, text) in zip(
        (366, 452, 538, 624),
        (("A", "forest"), ("B", "river"), ("C", "lake"), ("D", "hill")),
    ):
        draw_option(draw, y, letter, text, card["accent"])
    draw_operation_hint(draw, "SW1～SW4 选择 A～D，KEY4 提交", card["soft"], card["accent"], y0=752)


def draw_exercise_sentence(draw: ImageDraw.ImageDraw, card: dict) -> None:
    draw.text((82, 270), "Which sentence is correct?", font=font(29, bold=True), fill=INK, anchor="lm")
    draw.text((82, 315), "请选择正确的句子。", font=font(22, chinese=True), fill=MUTED, anchor="lm")
    options = [
        ("A", "There are a river."),
        ("B", "There is a river in the forest."),
        ("C", "There is some trees."),
        ("D", "There are a lake."),
    ]
    for y, (letter, text) in zip((366, 452, 538, 624), options):
        size = 21 if len(text) > 28 else 24
        draw_option(draw, y, letter, text, card["accent"], size=size)
    draw_operation_hint(draw, "SW1～SW4 选择 A～D，KEY4 提交", card["soft"], card["accent"], y0=752)


def draw_exercise_question(draw: ImageDraw.ImageDraw, card: dict) -> None:
    draw.text((82, 268), "Is there a bridge over the river?", font=font(26, bold=True), fill=INK, anchor="lm")
    draw.text((82, 313), "根据右图选择合适的回答。", font=font(22, chinese=True), fill=MUTED, anchor="lm")
    options = [
        ("A", "Yes, there is."),
        ("B", "No, there isn't."),
        ("C", "Yes, there are."),
        ("D", "No, there aren't."),
    ]
    for y, (letter, text) in zip((366, 452, 538, 624), options):
        draw_option(draw, y, letter, text, card["accent"], size=24)
    draw_operation_hint(draw, "SW1～SW4 选择 A～D，KEY4 提交", card["soft"], card["accent"], y0=752)


def draw_exercise_generic(draw: ImageDraw.ImageDraw, card: dict) -> None:
    question = str(card["question"])
    question_font = font(
        24 if len(question) > 35 else 27,
        bold=True,
        chinese=any(ord(character) > 127 for character in question),
    )
    draw.text((82, 270), question, font=question_font, fill=INK, anchor="lm")
    draw.text(
        (82, 315),
        str(card["question_cn"]),
        font=font(22, chinese=True),
        fill=MUTED,
        anchor="lm",
    )

    letters = "ABCD"
    for y, letter, option in zip((366, 452, 538, 624), letters, card["options"]):
        option_text = str(option)
        if len(option_text) > 37:
            option_size = 18
        elif len(option_text) > 29:
            option_size = 20
        elif len(option_text) > 22:
            option_size = 22
        else:
            option_size = 24
        draw_option(draw, y, letter, option_text, card["accent"], size=option_size)

    draw_operation_hint(
        draw,
        "SW1～SW4 选择 A～D，KEY4 提交",
        card["soft"],
        card["accent"],
        y0=752,
    )


def build_card(card: dict) -> Image.Image:
    photo_path = MATERIAL_DIR / card["photo"]
    if not photo_path.exists():
        raise FileNotFoundError(f"缺少实拍素材: {photo_path}")

    canvas = Image.new("RGB", (WIDTH, HEIGHT), PAPER)
    draw = ImageDraw.Draw(canvas)
    draw_header(draw, card)
    draw.rounded_rectangle((44, 150, 666, 880), radius=32, fill=WHITE, outline=LINE, width=3)
    draw_label(draw, card["label"], card["accent"])

    photo = Image.open(photo_path).convert("RGB")
    rounded_photo(canvas, photo, (698, 150, 1236, 880), card["focus"])

    learning_builders = {
        1: draw_learning_words,
        2: draw_learning_sentence,
        3: draw_learning_question,
    }
    if card["kind"] == "学习":
        learning_builders[card["number"]](draw, card)
    else:
        draw_exercise_generic(draw, card)
    return canvas


def build_contact_sheet(images: list[Image.Image]) -> Path:
    thumb = (480, 360)
    gap = 20
    label_h = 46
    rows = (len(CARDS) + 1) // 2
    sheet_h = gap + rows * (thumb[1] + label_h + gap)
    sheet = Image.new("RGB", (1020, sheet_h), "#D8DDD9")
    draw = ImageDraw.Draw(sheet)
    for index, (card, image) in enumerate(zip(CARDS, images)):
        col = index % 2
        row = index // 2
        x = gap + col * (thumb[0] + gap)
        y = gap + row * (thumb[1] + label_h + gap)
        preview = image.resize(thumb, Image.Resampling.LANCZOS)
        sheet.paste(preview, (x, y))
        draw.rectangle((x, y + thumb[1], x + thumb[0], y + thumb[1] + label_h), fill="white")
        draw.text(
            (x + 14, y + thumb[1] + label_h // 2),
            f'{card["number"]:02d}  英语{card["kind"]}  {card["title"]}',
            font=font(18, bold=True, chinese=True),
            fill=INK,
            anchor="lm",
        )
    path = PREVIEW_DIR / "english_nature_cards_contact_sheet.png"
    sheet.save(path, format="PNG", optimize=True)
    return path


def write_metadata() -> None:
    metadata = {
        "content_basis": "人教版 PEP 英语五年级上册 Unit 6 In a nature park 的词汇与核心句型方向；卡面不显示年级、单元或出版社。",
        "visible_cards": "3 张固定学习页 + 9 张练习题库页；正式运行时从三组题库各抽 1 题，共答 3 题。",
        "waveform_policy": "整个英语主题方案不显示声浪：静态图片不绘制，FPGA 运行时也不叠加。",
        "cards": CARDS,
        "photo_sources": SOURCES,
        "notes": [
            "参考图全部为真实摄影素材，不使用 AI 生成场景。",
            "字体使用 Windows 本机 Arial 与微软雅黑，不使用生成式图片文字。",
            "练习答案只记录在元数据中，不显示在题面。",
            "题库分为 vocabulary、sentence、question 三组，每组 3 题；答案位置经过打散。",
            "当前为视觉预览稿，尚未复制到 TF 卡，也未执行 FPGA/HDMI 上板验收。",
        ],
    }
    (OUTPUT_ROOT / "cards_and_sources.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
    )


def main() -> None:
    SOURCE_DIR.mkdir(parents=True, exist_ok=True)
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)

    images: list[Image.Image] = []
    for card in CARDS:
        image = build_card(card)
        images.append(image)
        stem = f'{card["number"]:02d}_英语_{card["kind"]}'
        image.save(SOURCE_DIR / f"{stem}.png", format="PNG", optimize=True)
        image.resize(DISPLAY_SIZE, Image.Resampling.LANCZOS).save(
            PREVIEW_DIR / f'{card["number"]:02d}.png', format="PNG", optimize=True
        )

    contact_sheet = build_contact_sheet(images)
    write_metadata()
    print("BUILD_PASS english_nature_cards_v1")
    print(f"Cards: {len(images)}; contact_sheet={contact_sheet}")
    print("Cards: 3 learning + 9 exercise pool; static waveform graphics: 0")


if __name__ == "__main__":
    main()
