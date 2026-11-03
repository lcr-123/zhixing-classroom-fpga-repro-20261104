"""Render the supplied single-page Anlogic cover as a VGA home BMP.

Keep lettering/logo proportions, adapt the decorative background to 4:3,
omit the bottom-left copyright text, and replace only 00.bmp in the TF ZIP.
Requires PyMuPDF and Pillow; the input PDF is never written.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
import zipfile

import pymupdf
from PIL import Image


def sha(data):
    return hashlib.sha256(data).hexdigest().upper()


def build(source, course_zip, output):
    output.mkdir(parents=True, exist_ok=True)
    document = pymupdf.open(source)
    if len(document) != 1 or tuple(document[0].rect) != (0, 0, 960, 540):
        raise ValueError("expected one 960x540 PDF page")
    page = document[0]
    stream = b"\n".join(document.xref_stream(x) for x in page.get_contents())
    text_objects = re.findall(rb"BT\b.*?\bET", stream, re.S)
    if len(text_objects) != 6 or b"/F1 9.96 Tf" not in text_objects[0] or "all rights reserved" not in page.get_text():
        raise ValueError("unexpected cover text structure")
    # Work on an in-memory stream. All original vectors and font resources stay
    # available, but the copyright text is excluded from every output layer.
    page.set_contents(page.get_contents()[0])
    content_xref = page.get_contents()[0]

    def render(content, alpha):
        document.update_stream(content_xref, content)
        pix = page.get_pixmap(matrix=pymupdf.Matrix(3, 3), alpha=alpha)
        return Image.frombytes("RGBA" if alpha else "RGB", (pix.width, pix.height), pix.samples)

    background = re.sub(rb"BT\b.*?\bET", b"", stream, flags=re.S)
    background = background.replace(b"/Image10 Do", b"")
    canvas = render(background, False).resize((640, 480), Image.Resampling.LANCZOS)
    # Uniform scale: unlike the background, title glyphs and logo cannot stretch.
    title = render(b"\n".join(b"q\n" + t + b"\nQ" for t in text_objects[1:]), True)
    title = title.resize((640, 360), Image.Resampling.LANCZOS)
    canvas.paste(title, (0, 60), title)
    logo = render(b"q\n157.83 0 0 31.613 88.173 471.53 cm\n/Image10 Do\nQ", True)
    logo = logo.resize((640, 360), Image.Resampling.LANCZOS)
    canvas.paste(logo, (0, 8), logo)
    canvas.save(output / "home_640x480.png")
    home = output / "00.bmp"
    canvas.save(home, format="BMP")
    data = home.read_bytes()
    assert len(data) == 921654 and data[:2] == b"BM"
    assert struct.unpack_from("<IiiHHI", data, 14) == (40, 640, 480, 1, 24, 0)
    with Image.open(home) as decoded:
        assert decoded.mode == "RGB" and decoded.tobytes() == canvas.tobytes()
    archive = output / "tf_card_home_practice_scaling.zip"
    files = {}
    with zipfile.ZipFile(course_zip) as old, zipfile.ZipFile(archive, "w", zipfile.ZIP_DEFLATED) as new:
        assert sorted(old.namelist()) == [f"{n:02d}.bmp" for n in range(13)]
        for n in range(13):
            name = f"{n:02d}.bmp"
            item = data if n == 0 else old.read(name)
            new.writestr(name, item)
            files[name] = {"bytes": len(item), "sha256": sha(item)}
    with zipfile.ZipFile(archive) as new, zipfile.ZipFile(course_zip) as old:
        assert new.testzip() is None
        assert all(new.read(f"{n:02d}.bmp") == old.read(f"{n:02d}.bmp") for n in range(1, 13))
    manifest = dict(source_pdf_sha256=sha(source.read_bytes()),
                    base_tf_zip_sha256=sha(course_zip.read_bytes()),
                    home_format="640x480 RGB24 bottom-up BI_RGB BMP",
                    copyright_text_removed=True, title_logo_aspect_preserved=True,
                    course_01_to_12_unchanged=True, files=files,
                    zip_sha256=sha(archive.read_bytes()), hardware_validation="NOT_RUN")
    (output / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (output / "SHA256SUMS.txt").write_text("".join(
        f"{sha(p.read_bytes())}  {p.name}\n" for p in sorted(output.iterdir())
        if p.is_file() and p.name != "SHA256SUMS.txt"), encoding="utf-8")
    print("PACKAGE_PASS", archive, manifest["zip_sha256"])


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--course-zip", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    build(args.source, args.course_zip, args.output)
