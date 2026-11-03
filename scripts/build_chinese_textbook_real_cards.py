from __future__ import annotations

import json
import math
import struct
from pathlib import Path

from PIL import Image, ImageDraw, ImageEnhance, ImageFilter, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT_ROOT = ROOT / "artifacts" / "chinese_textbook_real_cards"
PHOTO_DIR = OUTPUT_ROOT / "source_photos"
SOURCE_DIR = OUTPUT_ROOT / "source_png"
PREVIEW_DIR = OUTPUT_ROOT / "preview"
TF_DIR = OUTPUT_ROOT / "tf_card_ready"

WIDTH = 1280
HEIGHT = 960
DISPLAY_SIZE = (640, 480)

FONT_REGULAR = Path(r"C:\Windows\Fonts\msyh.ttc")
FONT_BOLD = Path(r"C:\Windows\Fonts\msyhbd.ttc")
FONT_KAITI = Path(r"C:\Windows\Fonts\STKAITI.TTF")

WHITE = "#FFFFFF"
INK = "#172033"
MUTED = "#5E687A"
PAPER = "#F5F2EA"
LIGHT = "#F8FAFC"
LINE = "#DCE3EA"

SUBJECTS = {
    "语文": {"accent": "#C9563A", "soft": "#F7E4DA"},
    "数学": {"accent": "#2473A6", "soft": "#DDEFF8"},
    "英语": {"accent": "#167C66", "soft": "#DDF2EB"},
    "音乐": {"accent": "#7A4EA3", "soft": "#EEE4F7"},
}

CARDS = [
    {
        "number": 1,
        "kind": "学习",
        "subject": "语文",
        "title": "《暮江吟》",
        "subtitle": "统编语文·四年级上册·第9课",
        "photo": "01_sunset_crescent.jpg",
        "answer": None,
    },
    {
        "number": 2,
        "kind": "学习",
        "subject": "数学",
        "title": "角的度量",
        "subtitle": "人教版数学·四年级上册·第三单元",
        "photo": "02_protractor.jpg",
        "answer": None,
    },
    {
        "number": 3,
        "kind": "学习",
        "subject": "英语",
        "title": "Unit 1  My classroom",
        "subtitle": "人教PEP英语·四年级上册",
        "photo": "03_beijing_classroom.jpg",
        "answer": None,
    },
    {
        "number": 4,
        "kind": "学习",
        "subject": "音乐",
        "title": "《小螺号》声音探索",
        "subtitle": "人教版音乐·四年级上册·第一单元",
        "photo": "04_conch_shell.jpg",
        "answer": None,
    },
    {
        "number": 5,
        "kind": "练习",
        "subject": "语文",
        "title": "《暮江吟》练习",
        "subtitle": "根据诗句选择正确答案",
        "photo": "01_sunset_crescent.jpg",
        "answer": "D",
    },
    {
        "number": 6,
        "kind": "练习",
        "subject": "数学",
        "title": "量角器读数",
        "subtitle": "中心对顶点，零线与一边重合",
        "photo": "02_protractor.jpg",
        "answer": "B",
    },
    {
        "number": 7,
        "kind": "练习",
        "subject": "英语",
        "title": "My classroom 练习",
        "subtitle": "读句子，选择合适的单词",
        "photo": "03_beijing_classroom.jpg",
        "answer": "B",
    },
    {
        "number": 8,
        "kind": "练习",
        "subject": "音乐",
        "title": "《小螺号》声音练习",
        "subtitle": "听同一段旋律，同时判断音高和波形",
        "photo": "04_conch_shell.jpg",
        "answer": "A",
    },
]

SOURCES = [
    {
        "file": "01_sunset_crescent.jpg",
        "title": "Sunset With Crescent Moon (39119081304)",
        "author": "Paul VanDerWerf",
        "license": "CC BY 2.0",
        "source_page": "https://commons.wikimedia.org/wiki/File:Sunset_With_Crescent_Moon_(39119081304).jpg",
        "use": "《暮江吟》学习卡与练习卡实景",
    },
    {
        "file": "02_protractor.jpg",
        "title": "Protractor.jpg",
        "author": "WikipediaMaster",
        "license": "CC BY-SA 3.0 / CC BY-SA 2.5",
        "source_page": "https://commons.wikimedia.org/wiki/File:Protractor.jpg",
        "use": "角的度量学习卡与练习卡实物",
    },
    {
        "file": "03_beijing_classroom.jpg",
        "title": "Beijing school classroom.jpg",
        "author": "Carla Antonini",
        "license": "CC BY-SA 3.0",
        "source_page": "https://commons.wikimedia.org/wiki/File:Beijing_school_classroom.jpg",
        "use": "PEP My classroom学习卡与练习卡实景",
    },
    {
        "file": "04_conch_shell.jpg",
        "title": "Conch shell 2.jpg",
        "author": "Brian0918",
        "license": "CC BY-SA 3.0 / GFDL",
        "source_page": "https://commons.wikimedia.org/wiki/File:Conch_shell_2.jpg",
        "use": "《小螺号》音乐学习卡与听音练习卡实物",
    },
]


def font(size: int, bold: bool = False, kai: bool = False) -> ImageFont.FreeTypeFont:
    path = FONT_KAITI if kai else (FONT_BOLD if bold else FONT_REGULAR)
    if not path.exists():
        raise FileNotFoundError(f"缺少字体: {path}")
    return ImageFont.truetype(str(path), size=size)


def cover_crop(
    image: Image.Image,
    box: tuple[int, int, int, int],
    focus_x: float = 0.5,
    focus_y: float = 0.5,
) -> Image.Image:
    x0, y0, x1, y1 = box
    target_w, target_h = x1 - x0, y1 - y0
    source = image.convert("RGB")
    scale = max(target_w / source.width, target_h / source.height)
    resized = source.resize(
        (round(source.width * scale), round(source.height * scale)),
        Image.Resampling.LANCZOS,
    )
    max_left = max(0, resized.width - target_w)
    left = round(max_left * min(1.0, max(0.0, focus_x)))
    max_top = max(0, resized.height - target_h)
    top = round(max_top * min(1.0, max(0.0, focus_y)))
    return resized.crop((left, top, left + target_w, top + target_h))


def rounded_photo(
    canvas: Image.Image,
    image: Image.Image,
    box: tuple[int, int, int, int],
    radius: int = 34,
    focus_x: float = 0.5,
    focus_y: float = 0.5,
    darken: float = 1.0,
) -> None:
    x0, y0, x1, y1 = box
    photo = cover_crop(image, box, focus_x=focus_x, focus_y=focus_y)
    if darken != 1.0:
        photo = ImageEnhance.Brightness(photo).enhance(darken)
    mask = Image.new("L", photo.size, 0)
    md = ImageDraw.Draw(mask)
    md.rounded_rectangle((0, 0, photo.width - 1, photo.height - 1), radius=radius, fill=255)
    canvas.paste(photo, (x0, y0), mask)


def draw_header(draw: ImageDraw.ImageDraw, card: dict) -> None:
    colors = SUBJECTS[card["subject"]]
    draw.rounded_rectangle((44, 34, 198, 92), radius=28, fill=colors["accent"])
    draw.text((121, 63), f'{card["subject"]}{card["kind"]}', font=font(27, True), fill=WHITE, anchor="mm")
    draw.text((226, 58), card["title"], font=font(42, True), fill=INK, anchor="lm")
    draw.text((226, 103), card["subtitle"], font=font(21), fill=MUTED, anchor="lm")
    draw.text((1236, 62), f'{card["number"]:02d}/08', font=font(25, True), fill=colors["accent"], anchor="rm")


def draw_footer(draw: ImageDraw.ImageDraw, card: dict) -> None:
    colors = SUBJECTS[card["subject"]]
    draw.line((44, 914, 1236, 914), fill=LINE, width=2)
    draw.text((48, 936), "四年级上册跨学科学习卡", font=font(17, True), fill=MUTED, anchor="lm")
    draw.ellipse((1118, 925, 1140, 947), fill=colors["accent"])
    draw.text((1154, 936), "实拍素材", font=font(17, True), fill=MUTED, anchor="lm")


def draw_label(draw: ImageDraw.ImageDraw, xy: tuple[int, int], text: str, accent: str) -> None:
    x, y = xy
    bbox = draw.textbbox((0, 0), text, font=font(20, True))
    width = bbox[2] - bbox[0] + 34
    draw.rounded_rectangle((x, y, x + width, y + 42), radius=20, fill=accent)
    draw.text((x + width // 2, y + 21), text, font=font(20, True), fill=WHITE, anchor="mm")


def draw_option(draw: ImageDraw.ImageDraw, top: int, letter: str, text: str, accent: str, width: int = 626) -> None:
    draw.rounded_rectangle((62, top, 62 + width, top + 76), radius=20, fill=LIGHT, outline=LINE, width=2)
    draw.ellipse((78, top + 12, 130, top + 64), fill=accent)
    draw.text((104, top + 38), letter, font=font(24, True), fill=WHITE, anchor="mm")
    size = 28 if len(text) <= 16 else 24
    draw.text((152, top + 38), text, font=font(size, True), fill=INK, anchor="lm")


def draw_waveform(draw: ImageDraw.ImageDraw, box: tuple[int, int, int, int], kind: str, color: str) -> None:
    x0, y0, x1, y1 = box
    mid = (y0 + y1) // 2
    draw.rounded_rectangle(box, radius=16, fill="#F7F4FB", outline="#D9CDE8", width=2)
    points: list[tuple[int, int]] = []
    for x in range(x0 + 14, x1 - 14):
        phase = (x - (x0 + 14)) / max(1, (x1 - x0 - 28)) * 2.0
        if kind == "方波":
            value = -1 if (phase % 1.0) < 0.5 else 1
        elif kind == "三角波":
            value = 4 * abs((phase % 1.0) - 0.5) - 1
        else:
            value = math.sin(phase * math.tau)
        y = round(mid + value * (y1 - y0) * 0.28)
        points.append((x, y))
    draw.line(points, fill=color, width=5, joint="curve")


def draw_angle_diagram(draw: ImageDraw.ImageDraw, center: tuple[int, int], degrees: int, accent: str) -> None:
    cx, cy = center
    radius = 150
    draw.line((cx, cy, cx + radius, cy), fill=INK, width=8)
    end_x = cx + round(radius * math.cos(math.radians(degrees)))
    end_y = cy - round(radius * math.sin(math.radians(degrees)))
    draw.line((cx, cy, end_x, end_y), fill=accent, width=8)
    draw.ellipse((cx - 9, cy - 9, cx + 9, cy + 9), fill=accent)
    draw.arc((cx - 86, cy - 86, cx + 86, cy + 86), start=360 - degrees, end=360, fill=accent, width=7)
    draw.text((cx + 98, cy - 58), "?°", font=font(34, True), fill=accent, anchor="mm")


def build_learning_chinese(canvas: Image.Image, draw: ImageDraw.ImageDraw, photo: Image.Image, card: dict) -> None:
    accent = SUBJECTS["语文"]["accent"]
    rounded_photo(canvas, photo, (698, 150, 1236, 880), focus_x=0.0, focus_y=0.52, darken=0.88)
    draw.rounded_rectangle((44, 150, 666, 880), radius=32, fill="#FFFCF7", outline="#E7D8CE", width=3)
    draw_label(draw, (76, 180), "古诗学习", accent)
    draw.text((355, 250), "暮江吟", font=font(54, True, kai=True), fill=INK, anchor="mm")
    draw.text((355, 302), "唐·白居易", font=font(25, kai=True), fill=MUTED, anchor="mm")
    lines = ["一道残阳铺水中", "半江瑟瑟半江红", "可怜九月初三夜", "露似真珠月似弓"]
    y = 390
    for line in lines:
        draw.text((355, y), line, font=font(42, kai=True), fill=INK, anchor="mm")
        y += 82
    draw.rounded_rectangle((86, 740, 624, 836), radius=24, fill=SUBJECTS["语文"]["soft"])
    draw.text((112, 772), "理解重点", font=font(23, True), fill=accent)
    draw.text((112, 812), "残阳映江，露珠如珍珠，弯月像弓。", font=font(25), fill=INK)


def build_learning_math(canvas: Image.Image, draw: ImageDraw.ImageDraw, photo: Image.Image, card: dict) -> None:
    accent = SUBJECTS["数学"]["accent"]
    rounded_photo(canvas, photo, (710, 168, 1236, 570), focus_y=0.48)
    draw.rounded_rectangle((44, 150, 674, 880), radius=32, fill=WHITE, outline=LINE, width=3)
    draw_label(draw, (76, 180), "操作步骤", accent)
    steps = [
        ("1", "量角器中心对准角的顶点"),
        ("2", "0°刻度线与角的一条边重合"),
        ("3", "另一条边指向的刻度就是角度"),
    ]
    y = 264
    for number, text in steps:
        draw.ellipse((82, y, 138, y + 56), fill=accent)
        draw.text((110, y + 28), number, font=font(25, True), fill=WHITE, anchor="mm")
        draw.text((162, y + 28), text, font=font(28, True), fill=INK, anchor="lm")
        y += 105
    draw.rounded_rectangle((82, 604, 636, 832), radius=24, fill=SUBJECTS["数学"]["soft"])
    draw.text((110, 638), "读数提醒", font=font(25, True), fill=accent)
    draw.text((110, 690), "先确定从哪一侧的 0° 开始，", font=font(27), fill=INK)
    draw.text((110, 738), "再读对应的内圈或外圈刻度。", font=font(27), fill=INK)
    draw_angle_diagram(draw, (962, 792), 60, accent)


def build_learning_english(canvas: Image.Image, draw: ImageDraw.ImageDraw, photo: Image.Image, card: dict) -> None:
    accent = SUBJECTS["英语"]["accent"]
    rounded_photo(canvas, photo, (630, 150, 1236, 880), focus_y=0.45, darken=0.92)
    draw.rounded_rectangle((44, 150, 610, 880), radius=32, fill=WHITE, outline=LINE, width=3)
    draw_label(draw, (76, 180), "词汇与句型", accent)
    pairs = [
        ("classroom", "教室"),
        ("window", "窗户"),
        ("blackboard", "黑板"),
        ("desk", "书桌"),
        ("chair", "椅子"),
    ]
    y = 258
    for english, chinese in pairs:
        draw.rounded_rectangle((78, y, 574, y + 68), radius=17, fill=LIGHT)
        draw.text((102, y + 34), english, font=font(29, True), fill=accent, anchor="lm")
        draw.text((540, y + 34), chinese, font=font(27), fill=INK, anchor="rm")
        y += 82
    draw.rounded_rectangle((78, 696, 574, 834), radius=22, fill=SUBJECTS["英语"]["soft"])
    draw.text((102, 728), "重点句型", font=font(23, True), fill=accent)
    draw.text((102, 770), "Where is the schoolbag?", font=font(27, True), fill=INK)
    draw.text((102, 812), "It's under the desk.", font=font(27), fill=INK)


def build_learning_music(canvas: Image.Image, draw: ImageDraw.ImageDraw, photo: Image.Image, card: dict) -> None:
    accent = SUBJECTS["音乐"]["accent"]
    rounded_photo(canvas, photo, (760, 152, 1236, 880), focus_y=0.45)
    draw.rounded_rectangle((44, 150, 728, 880), radius=32, fill=WHITE, outline=LINE, width=3)
    draw_label(draw, (76, 180), "歌曲与声音", accent)
    draw.text((80, 256), "学习内容", font=font(28, True), fill=INK)
    draw.text((80, 307), "歌曲主题：《小螺号》", font=font(31, True), fill=accent)
    draw.text((80, 353), "观察海螺，感受明亮、活泼的音乐形象。", font=font(25), fill=INK)
    controls = [
        ("SW2 SW1", "00低音  01原调  10/11高音"),
        ("SW4 SW3", "00方波  01三角波  10/11正弦波"),
        ("KEY2", "循环调节弱、中、强"),
    ]
    y = 420
    for key, action in controls:
        draw.rounded_rectangle((80, y, 688, y + 72), radius=22, fill=SUBJECTS["音乐"]["soft"], outline="#D6C3E7", width=2)
        draw.text((106, y + 36), key, font=font(24, True), fill=accent, anchor="lm")
        draw.text((272, y + 36), action, font=font(23, True), fill=INK, anchor="lm")
        y += 88
    draw.rounded_rectangle((80, 704, 688, 836), radius=24, fill="#F5F0F9")
    draw.text((106, 742), "边听《小螺号》边调节", font=font(23, True), fill=accent)
    draw.text((106, 781), "讲解结束后操作；KEY4进入综合练习。", font=font(22, True), fill=INK)
    draw.text((106, 815), "HDMI声音与底部实时波形同步变化。", font=font(22), fill=INK)


def build_exercise_chinese(canvas: Image.Image, draw: ImageDraw.ImageDraw, photo: Image.Image, card: dict) -> None:
    accent = SUBJECTS["语文"]["accent"]
    rounded_photo(canvas, photo, (754, 156, 1236, 880), focus_x=0.0, focus_y=0.52, darken=0.83)
    draw.rounded_rectangle((44, 150, 722, 880), radius=32, fill=WHITE, outline=LINE, width=3)
    draw_label(draw, (72, 180), "单项选择", accent)
    draw.text((72, 250), "哪句诗写出了弯月像弓？", font=font(35, True), fill=INK)
    options = [
        ("A", "一道残阳铺水中"),
        ("B", "半江瑟瑟半江红"),
        ("C", "可怜九月初三夜"),
        ("D", "露似真珠月似弓"),
    ]
    y = 334
    for letter, text in options:
        draw_option(draw, y, letter, text, accent, width=606)
        y += 94
    draw.rounded_rectangle((72, 744, 688, 832), radius=22, fill=SUBJECTS["语文"]["soft"])
    draw.text((96, 788), "使用 SW1～SW4 选择 A～D，KEY4 提交", font=font(24, True), fill=accent, anchor="lm")


def build_exercise_math(canvas: Image.Image, draw: ImageDraw.ImageDraw, photo: Image.Image, card: dict) -> None:
    accent = SUBJECTS["数学"]["accent"]
    rounded_photo(canvas, photo, (716, 152, 1236, 500), focus_y=0.48, darken=0.92)
    draw.rounded_rectangle((44, 150, 686, 880), radius=32, fill=WHITE, outline=LINE, width=3)
    draw_label(draw, (72, 180), "读图计算", accent)
    draw.text((72, 250), "图中的角是多少度？", font=font(37, True), fill=INK)
    draw_angle_diagram(draw, (282, 520), 60, accent)
    options = [("A", "30°"), ("B", "60°"), ("C", "90°"), ("D", "120°")]
    positions = [(72, 672), (374, 672), (72, 768), (374, 768)]
    for (letter, value), (x, y) in zip(options, positions):
        draw.rounded_rectangle((x, y, x + 274, y + 76), radius=20, fill=LIGHT, outline=LINE, width=2)
        draw.ellipse((x + 14, y + 12, x + 66, y + 64), fill=accent)
        draw.text((x + 40, y + 38), letter, font=font(24, True), fill=WHITE, anchor="mm")
        draw.text((x + 168, y + 38), value, font=font(30, True), fill=INK, anchor="mm")
    draw.rounded_rectangle((716, 536, 1236, 880), radius=32, fill=SUBJECTS["数学"]["soft"])
    draw.text((756, 584), "作答提示", font=font(28, True), fill=accent)
    draw.text((756, 642), "1. 中心是否对准顶点？", font=font(27), fill=INK)
    draw.text((756, 700), "2. 从哪一侧的 0° 起读？", font=font(27), fill=INK)
    draw.text((756, 758), "3. 另一条边指向多少度？", font=font(27), fill=INK)


def build_exercise_english(canvas: Image.Image, draw: ImageDraw.ImageDraw, photo: Image.Image, card: dict) -> None:
    accent = SUBJECTS["英语"]["accent"]
    rounded_photo(canvas, photo, (704, 150, 1236, 880), focus_y=0.45, darken=0.88)
    draw.rounded_rectangle((44, 150, 674, 880), radius=32, fill=WHITE, outline=LINE, width=3)
    draw_label(draw, (72, 180), "Choose the word", accent)
    draw.text((72, 250), "The students sit at their ____.", font=font(33, True), fill=INK)
    draw.text((72, 303), "学生们坐在他们的____旁。", font=font(26), fill=MUTED)
    options = [("A", "windows"), ("B", "desks"), ("C", "doors"), ("D", "lights")]
    y = 368
    for letter, value in options:
        draw_option(draw, y, letter, value, accent, width=566)
        y += 92
    draw.rounded_rectangle((72, 752, 638, 832), radius=22, fill=SUBJECTS["英语"]["soft"])
    draw.text((98, 792), "结合右侧真实教室照片作答", font=font(25, True), fill=accent, anchor="lm")


def build_exercise_music(canvas: Image.Image, draw: ImageDraw.ImageDraw, photo: Image.Image, card: dict) -> None:
    accent = SUBJECTS["音乐"]["accent"]
    rounded_photo(canvas, photo, (804, 150, 1236, 880), focus_y=0.45, darken=0.94)
    draw.rounded_rectangle((44, 150, 772, 880), radius=32, fill=WHITE, outline=LINE, width=3)
    draw_label(draw, (72, 180), "听音综合挑战", accent)
    draw.text((72, 246), "听《小螺号》片段：音高和波形是什么？", font=font(31, True), fill=INK)
    draw.text((72, 296), "一次选择，同时判断两个声音特征。", font=font(24), fill=MUTED)
    rows = [
        ("A", "高音 + 方波"),
        ("B", "中音 + 三角波"),
        ("C", "低音 + 正弦波"),
        ("D", "中音 + 正弦波"),
    ]
    y = 344
    for letter, title in rows:
        draw_option(draw, y, letter, title, accent, width=650)
        y += 92
    draw.rounded_rectangle((72, 728, 738, 834), radius=22, fill=SUBJECTS["音乐"]["soft"])
    draw.text((100, 762), "题音由FPGA实时合成，不是录音。", font=font(23, True), fill=accent)
    draw.text((100, 804), "SW1～SW4选A～D，KEY4提交。", font=font(23), fill=INK)


def build_card(card: dict) -> Image.Image:
    photo_path = PHOTO_DIR / card["photo"]
    if not photo_path.exists():
        raise FileNotFoundError(f"缺少实拍素材: {photo_path}")
    photo = Image.open(photo_path).convert("RGB")
    canvas = Image.new("RGB", (WIDTH, HEIGHT), PAPER)
    draw = ImageDraw.Draw(canvas)
    draw_header(draw, card)

    builders = {
        1: build_learning_chinese,
        2: build_learning_math,
        3: build_learning_english,
        4: build_learning_music,
        5: build_exercise_chinese,
        6: build_exercise_math,
        7: build_exercise_english,
        8: build_exercise_music,
    }
    builders[card["number"]](canvas, draw, photo, card)
    draw_footer(draw, card)
    return canvas


def validate_bmp(path: Path, expected_size: tuple[int, int]) -> None:
    data = path.read_bytes()
    if data[:2] != b"BM":
        raise ValueError(f"不是BMP文件: {path}")
    width, height = struct.unpack_from("<ii", data, 18)
    bpp = struct.unpack_from("<H", data, 28)[0]
    compression = struct.unpack_from("<I", data, 30)[0]
    if (width, height) != expected_size or height <= 0 or bpp != 24 or compression != 0:
        raise ValueError(
            f"BMP格式不符合要求: {path}: {width}x{height}, bpp={bpp}, compression={compression}"
        )


def build_contact_sheet(cards: list[Image.Image]) -> None:
    thumb_size = (480, 360)
    gap = 20
    label_h = 48
    sheet_w = thumb_size[0] * 2 + gap * 3
    sheet_h = (thumb_size[1] + label_h) * 4 + gap * 5
    sheet = Image.new("RGB", (sheet_w, sheet_h), "#DDE3E9")
    draw = ImageDraw.Draw(sheet)
    for index, (card, image) in enumerate(zip(CARDS, cards)):
        col = index % 2
        row = index // 2
        x = gap + col * (thumb_size[0] + gap)
        y = gap + row * (thumb_size[1] + label_h + gap)
        preview = image.resize(thumb_size, Image.Resampling.LANCZOS)
        sheet.paste(preview, (x, y))
        draw.rectangle((x, y + thumb_size[1], x + thumb_size[0], y + thumb_size[1] + label_h), fill=WHITE)
        draw.text(
            (x + 16, y + thumb_size[1] + label_h // 2),
            f'{card["number"]:02d}  {card["subject"]}{card["kind"]}  {card["title"]}',
            font=font(20, True),
            fill=INK,
            anchor="lm",
        )
    sheet.save(PREVIEW_DIR / "eight_cards_contact_sheet.png", format="PNG", optimize=True)


def write_metadata() -> None:
    metadata = {
        "curriculum": {
            "语文": "统编语文四年级上册第9课《古诗三首》之《暮江吟》",
            "数学": "人教版数学四年级上册第三单元《角的度量》",
            "英语": "人教PEP英语（三年级起点）四年级上册 Unit 1 My classroom",
            "音乐": "人教版音乐（简谱）四年级上册第一单元《东海渔歌》之《小螺号》",
        },
        "flow": "01-04学习，05-08对应练习",
        "cards": CARDS,
        "photo_sources": SOURCES,
        "notes": [
            "所有底图为真实照片或实物照片，不含AI生成素材。",
            "未复制教材整页；知识点依据正式教材重新排版。",
            "音乐学习与练习均由FPGA实时演奏《小螺号》教学片段；练习同时辨别音高和波形，不使用第三方录音。",
        ],
    }
    (OUTPUT_ROOT / "cards_and_sources.json").write_text(
        json.dumps(metadata, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    lines = [
        "# 八张跨学科教材卡素材来源",
        "",
        "全部画面使用真实照片或实物照片，不含AI生成素材。教材知识点重新排版，未复制教材整页。",
        "",
    ]
    for source in SOURCES:
        lines.extend(
            [
                f'## {source["file"]}',
                "",
                f'- 素材：{source["title"]}',
                f'- 作者：{source["author"]}',
                f'- 许可：{source["license"]}',
                f'- 用途：{source["use"]}',
                f'- 来源：{source["source_page"]}',
                "",
            ]
        )
    (OUTPUT_ROOT / "SOURCES.md").write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    for directory in (SOURCE_DIR, PREVIEW_DIR, TF_DIR):
        directory.mkdir(parents=True, exist_ok=True)

    rendered: list[Image.Image] = []
    for card in CARDS:
        image = build_card(card)
        rendered.append(image)
        png_path = SOURCE_DIR / f'{card["number"]:02d}_{card["subject"]}_{card["kind"]}.png'
        image.save(png_path, format="PNG", optimize=True)

        display = image.resize(DISPLAY_SIZE, Image.Resampling.LANCZOS)
        display.save(PREVIEW_DIR / f'{card["number"]:02d}.png', format="PNG", optimize=True)
        bmp_path = TF_DIR / f'{card["number"]:02d}.bmp'
        display.save(bmp_path, format="BMP")
        validate_bmp(bmp_path, DISPLAY_SIZE)

    build_contact_sheet(rendered)
    write_metadata()
    print("BUILD_PASS chinese_textbook_real_cards")
    print("Cards: 8; flow: 01-04 learning, 05-08 exercise")
    print("Display BMP: 640x480, 24-bit BI_RGB, positive height")


if __name__ == "__main__":
    main()
