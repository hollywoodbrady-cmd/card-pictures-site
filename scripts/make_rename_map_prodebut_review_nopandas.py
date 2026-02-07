import argparse
import csv
import re
from pathlib import Path

from PIL import Image, ImageOps, ImageEnhance
import pytesseract
import difflib

STOPWORDS = {
    "topps", "chrome", "bowman", "pro", "debut", "prospects", "draft",
    "base", "insert", "auto", "autograph", "refractor", "parallel", "numbered"
}

def slugify(s: str) -> str:
    s = (s or "").strip().lower()
    s = re.sub(r"[’'`]", "", s)
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    return s

def clean_text(s: str) -> str:
    s = (s or "").replace("\n", " ").replace("\r", " ")
    s = re.sub(r"\s{2,}", " ", s).strip()
    return s

def norm(s: str) -> str:
    s = (s or "").lower()
    s = re.sub(r"[^a-z\s\-]", " ", s)
    s = re.sub(r"\s{2,}", " ", s).strip()
    return s

def load_player_dictionary_from_csv(checklist_csv: Path) -> list[str]:
    players = set()
    with checklist_csv.open("r", encoding="utf-8-sig", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            for cell in row:
                v = (cell or "").strip()
                # crude "First Last" name detection
                if re.match(r"^[A-Za-z][A-Za-z\.\-']+\s+[A-Za-z][A-Za-z\.\-']+", v):
                    # ignore column headers / junk
                    if len(v) <= 40:
                        players.add(v)
    return sorted(players)

def preprocess_text_region(im: Image.Image) -> Image.Image:
    im = ImageOps.exif_transpose(im).convert("L")
    im = ImageEnhance.Contrast(im).enhance(3.0)
    im = ImageEnhance.Sharpness(im).enhance(2.0)
    return im

def ocr_name_hint(img_path: Path, timeout_sec: float = 2.0) -> str:
    img = Image.open(img_path)
    img = ImageOps.exif_transpose(img)

    # ensure portrait
    if img.width > img.height:
        img = img.rotate(90, expand=True)

    w, h = img.size

    # bottom nameplate-ish region (tweak if needed)
    box = (int(w * 0.16), int(h * 0.78), int(w * 0.84), int(h * 0.92))
    crop = img.crop(box)
    crop = preprocess_text_region(crop)
    crop = crop.resize((crop.width * 2, crop.height * 2))

    cfg = "--oem 3 --psm 6"
    try:
        txt = pytesseract.image_to_string(crop, config=cfg, timeout=timeout_sec)
    except Exception:
        return ""

    txt = clean_text(txt)
    words = re.findall(r"[A-Za-z][A-Za-z\-']+", txt)
    words = [w.strip("'") for w in words if w.strip("'").lower() not in STOPWORDS]
    return " ".join(words[:6])

def best_dictionary_match(hint: str, players: list[str]) -> tuple[str, float]:
    h = norm(hint)
    if not h:
        return ("", 0.0)

    best_name = ""
    best_ratio = 0.0
    for p in players:
        r = difflib.SequenceMatcher(None, h, norm(p)).ratio()
        if r > best_ratio:
            best_ratio = r
            best_name = p
    return best_name, best_ratio

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True, help="Folder of FRONT images")
    ap.add_argument("--out", required=True, help="Output CSV path (rename map)")
    ap.add_argument("--checklist-csv", required=True, help="Checklist saved as CSV UTF-8")
    ap.add_argument("--tesseract", default=r"C:\Program Files\Tesseract-OCR\tesseract.exe")
    ap.add_argument("--review", action="store_true", help="Interactive review/confirm")
    ap.add_argument("--min-ratio", type=float, default=0.72, help="Auto-accept match if >= this ratio")
    args = ap.parse_args()

    pytesseract.pytesseract.tesseract_cmd = args.tesseract

    src_dir = Path(args.dir)
    out_csv = Path(args.out)
    checklist_csv = Path(args.checklist_csv)

    if not src_dir.exists():
        raise SystemExit(f"Folder not found: {src_dir}")
    if not checklist_csv.exists():
        raise SystemExit(f"Checklist CSV not found: {checklist_csv}")

    players = load_player_dictionary_from_csv(checklist_csv)
    if not players:
        raise SystemExit("No player names found in checklist CSV. (Did you export the right sheet?)")

    files = sorted([p for p in src_dir.iterdir() if p.is_file() and p.suffix.lower() in [".jpg", ".jpeg", ".png"]])

    rows = []
    for f in files:
        hint = ocr_name_hint(f)
        match, ratio = best_dictionary_match(hint, players)
        proposed = match if ratio >= args.min_ratio else ""

        if args.review:
            print("\n" + "=" * 70)
            print(f"FILE: {f.name}")
            print(f"OCR hint: {hint!r}")
            print(f"Best match: {match!r}  (ratio={ratio:.2f})")
            prompt = f"Enter to accept [{proposed}] or type correct name: " if proposed else "Type correct player name: "
            typed = input(prompt).strip()
            final_player = typed if typed else proposed
        else:
            final_player = proposed

        base_slug = slugify(final_player) if final_player else "unknown-player"
        new_name = f"{base_slug}__pro-debut__front.jpg"

        rows.append({
            "OldName": f.name,
            "NewName": new_name,
            "Player": final_player,
            "Hint": hint,
            "MatchRatio": f"{ratio:.2f}",
        })

    out_csv.parent.mkdir(parents=True, exist_ok=True)
    with out_csv.open("w", newline="", encoding="utf-8") as fp:
        w = csv.DictWriter(fp, fieldnames=["OldName","NewName","Player","Hint","MatchRatio"])
        w.writeheader()
        w.writerows(rows)

    print(f"\nWrote rename map: {out_csv}")
    print(f"Files processed: {len(files)}")

if __name__ == "__main__":
    main()
