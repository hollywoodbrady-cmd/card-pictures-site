\
#!/usr/bin/env python3
"""
Rename/copy card images using a metadata CSV.

Workflow:
1) Fill out cards_metadata_template.csv (player_name, team, parallel, numbered_to, etc.)
2) Run:
   python rename_from_csv.py --root originals --csv cards_metadata_template.csv --out renamed

Filename pattern (parts omitted if blank):
{set}_{player}_{team}_{cardno}_{subset}_{parallel}_{auto}_{serialofnumbered}_{other}_front.jpg
and ..._back.jpg

Examples:
Topps Cosmic 2025_Shohei Ohtani_Dodgers_#123_Galactic_Refractor_03of50_front.jpg
Topps Cosmic 2025_Elly De La Cruz_Reds_#200_Rookie_auto_01of10_back.jpg
"""
import argparse, csv, os, re, shutil
from pathlib import Path

IMG_EXTS = {".jpg",".jpeg",".png",".webp",".tif",".tiff",".heic"}

def slug_part(s: str) -> str:
    s = (s or "").strip()
    # keep letters/numbers/spaces/.-# and collapse whitespace
    s = re.sub(r"[^\w\s\-.#]+", "", s, flags=re.UNICODE)
    s = re.sub(r"\s+", " ", s).strip()
    # replace spaces with underscores
    s = s.replace(" ", "_")
    # trim repeated underscores
    s = re.sub(r"_+", "_", s)
    return s

def build_name(row: dict, side: str) -> str:
    set_name = slug_part(row.get("set_name",""))
    player   = slug_part(row.get("player_name",""))
    team     = slug_part(row.get("team",""))
    cardno   = row.get("card_number","").strip()
    if cardno and not cardno.startswith("#"):
        cardno = f"#{cardno}"
    cardno = slug_part(cardno)

    subset   = slug_part(row.get("subset",""))
    parallel = slug_part(row.get("parallel",""))
    auto     = slug_part(row.get("auto",""))
    other    = slug_part(row.get("other_desc",""))

    numbered_to = (row.get("numbered_to","") or "").strip()
    serial_num  = (row.get("serial_number","") or "").strip()

    serial = ""
    if numbered_to:
        if serial_num:
            serial = f"{serial_num}of{numbered_to}"
        else:
            serial = f"of{numbered_to}"
    serial = slug_part(serial)

    parts = [set_name, player, team, cardno, subset, parallel, auto, serial, other]
    parts = [p for p in parts if p]
    base = "_".join(parts) if parts else f"card_{row.get('card_id','0000')}"
    return f"{base}_{side}"

def copy_with_ext(src: Path, dst_base: Path) -> Path:
    ext = src.suffix.lower()
    if ext not in IMG_EXTS:
        ext = ".jpg"
    dst = dst_base.with_suffix(ext)
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    return dst

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True, help="Folder that contains extracted originals (relative paths from CSV).")
    ap.add_argument("--csv", required=True, help="Metadata CSV")
    ap.add_argument("--out", required=True, help="Output folder for renamed copies")
    ap.add_argument("--overwrite", action="store_true", help="Overwrite existing files")
    args = ap.parse_args()

    root = Path(args.root)
    out  = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    with open(args.csv, newline="", encoding="utf-8") as f:
        rdr = csv.DictReader(f)
        for row in rdr:
            front_rel = row.get("front_original","").strip()
            back_rel  = row.get("back_original","").strip()

            if front_rel:
                src = root / Path(front_rel)
                if src.exists():
                    dst_base = out / build_name(row, "front")
                    dst = dst_base.with_suffix(src.suffix.lower())
                    if dst.exists() and not args.overwrite:
                        print(f"SKIP exists: {dst.name}")
                    else:
                        copy_with_ext(src, dst_base)
                        print(f"OK  front -> {dst_base.name}{src.suffix.lower()}")
                else:
                    print(f"MISS front source: {src}")

            if back_rel:
                src = root / Path(back_rel)
                if src.exists():
                    dst_base = out / build_name(row, "back")
                    dst = dst_base.with_suffix(src.suffix.lower())
                    if dst.exists() and not args.overwrite:
                        print(f"SKIP exists: {dst.name}")
                    else:
                        copy_with_ext(src, dst_base)
                        print(f"OK  back  -> {dst_base.name}{src.suffix.lower()}")
                else:
                    print(f"MISS back source: {src}")

if __name__ == "__main__":
    main()
