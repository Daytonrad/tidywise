"""Collect context for a file: source URL, text excerpt and, where useful, an image for the model."""
from __future__ import annotations

import base64
import plistlib
import re
import subprocess
import tempfile
import zipfile
from datetime import datetime
from pathlib import Path

from .config import short_path

TEXTUTIL_EXT = {".docx", ".doc", ".rtf", ".rtfd", ".odt", ".html", ".htm", ".webarchive"}
PLAIN_EXT = {
    ".txt", ".md", ".csv", ".tsv", ".json", ".xml", ".yaml", ".yml", ".toml", ".py", ".js", ".ts", ".tsx",
    ".jsx", ".css", ".sh", ".swift", ".java", ".c", ".cpp", ".h", ".go", ".rs", ".sql", ".log", ".tex", ".ini",
}
IMAGE_EXT = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".gif", ".webp", ".tif", ".tiff", ".bmp"}
TEXT_LIMIT = 2500


def _run(cmd: list[str], timeout: float = 30) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, timeout=timeout)


def where_froms(p: Path) -> list[str]:
    """macOS stores the source URL(s) of a download as an extended attribute."""
    try:
        r = _run(["xattr", "-px", "com.apple.metadata:kMDItemWhereFroms", str(p)], timeout=5)
        if r.returncode != 0:
            return []
        data = bytes.fromhex(r.stdout.decode().replace("\n", "").replace(" ", ""))
        val = plistlib.loads(data)
        return [str(v) for v in val if v] if isinstance(val, list) else []
    except Exception:  # noqa: BLE001
        return []


def _clean(text: str) -> str:
    text = re.sub(r"[ \t]+", " ", text)
    text = re.sub(r"\n\s*\n+", "\n", text)
    return text.strip()[:TEXT_LIMIT]


def _pdf_text(p: Path) -> str:
    try:
        import logging

        from pypdf import PdfReader
        logging.getLogger("pypdf").setLevel(logging.ERROR)
    except ImportError:
        return ""
    try:
        reader = PdfReader(str(p))
        parts = []
        for page in reader.pages[:4]:
            parts.append(page.extract_text() or "")
            if sum(map(len, parts)) > TEXT_LIMIT:
                break
        return _clean("\n".join(parts))
    except Exception:  # noqa: BLE001
        return ""


def _office_xml_text(p: Path, prefix: str) -> str:
    try:
        with zipfile.ZipFile(p) as z:
            names = sorted(n for n in z.namelist() if n.startswith(prefix) and n.endswith(".xml"))
            out = []
            for n in names[:15]:
                xml = z.read(n).decode("utf-8", errors="replace")
                pieces = re.findall(r"<a:t>([^<]*)</a:t>|<t[^>]*>([^<]*)</t>", xml)
                out.append(" ".join(a or b for a, b in pieces))
            return _clean("\n".join(out))
    except Exception:  # noqa: BLE001
        return ""


def _zip_listing(p: Path) -> str:
    try:
        with zipfile.ZipFile(p) as z:
            names = z.namelist()
        return "Archive contents: " + ", ".join(names[:25]) + (f" … (+{len(names) - 25})" if len(names) > 25 else "")
    except Exception:  # noqa: BLE001
        return ""


def text_excerpt(p: Path) -> str:
    ext = p.suffix.lower()
    try:
        if ext == ".pdf":
            return _pdf_text(p)
        if ext in TEXTUTIL_EXT:
            r = _run(["textutil", "-noload", "-convert", "txt", "-stdout", str(p)])
            return _clean(r.stdout.decode("utf-8", errors="replace")) if r.returncode == 0 else ""
        if ext == ".pptx":
            return _office_xml_text(p, "ppt/slides/slide")
        if ext == ".xlsx":
            return _office_xml_text(p, "xl/sharedStrings")
        if ext in PLAIN_EXT:
            with open(p, "rb") as fh:
                return _clean(fh.read(TEXT_LIMIT * 2).decode("utf-8", errors="replace"))
        if zipfile.is_zipfile(p):  # .zip, but also containers that are zip files underneath
            return _zip_listing(p)
    except Exception:  # noqa: BLE001
        return ""
    return ""


def image_b64(p: Path) -> str | None:
    """Image (or first PDF page) as a downscaled JPEG for the model."""
    with tempfile.TemporaryDirectory() as td:
        out = Path(td) / "img.jpg"
        r = _run(["sips", "-s", "format", "jpeg", "-Z", "1024", str(p), "--out", str(out)], timeout=60)
        if r.returncode != 0 or not out.exists():
            return None
        return base64.b64encode(out.read_bytes()).decode()


def human_size(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if n < 1024:
            return f"{n:.0f} {unit}"
        n /= 1024
    return f"{n:.1f} TB"


def describe(p: Path) -> tuple[dict, list[str]]:
    st = p.stat()
    ext = p.suffix.lower()
    info = {
        "filename": p.name,
        "extension": ext or "(none)",
        "size": human_size(st.st_size),
        "folder": short_path(p.parent),
        "created": datetime.fromtimestamp(getattr(st, "st_birthtime", st.st_mtime)).strftime("%Y-%m-%d"),
    }
    sources = where_froms(p)
    if sources:
        info["downloaded_from"] = sources[:2]
    images: list[str] = []
    text = text_excerpt(p)
    if text:
        info["text_excerpt"] = text
    if ext in IMAGE_EXT or (ext == ".pdf" and len(text) < 80):
        img = image_b64(p)
        if img:
            images.append(img)
    return info, images
