import re
import os
import shutil
from pathlib import Path
import pandas as pd

SET_TAG = "topps-cosmic"

# --- helpers ---
def slug(s: str) -> str:
    s = (s or "").strip().lower()
    s = s.replace("&", "and")
    s = re.sub(r"[’']", "", s)
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = re.sub(r"-{2,}", "-", s).strip("-")
    return s or "unknown"

def clean_player(p: str) -> str:
    # checklist often has "Name," with trailing comma
    p = (p or "").strip()
    p = re.sub(r",\s*$", "", p)
    return p

def is_header_row(a, b, c) -> bool:
    # rows like: "Planetary Pursuit" then blanks
    return isinstance(a, str) and a.strip() and (pd.isna(b) or b == "") and (pd.isna(c) or c == "")

def is_code(x) -> bool:
    return isinstance(x, str) and bool(re.match(r"^[A-Za-z]{1,6}-\d+$", x.strip()))

def parse_full_checklist_base(df: pd.DataFrame):
    # Expected columns: [Base Set, Unnamed: 1, Unnamed: 2, ...]
    out = {}
    current_subset = "Base"
    for _, row in df.iterrows():
        a = row.iloc[0] if len(row) > 0 else None
        b = row.iloc[1] if len(row) > 1 else None
        c = row.iloc[2] if len(row) > 2 else None

        if is_header_row(a, b, c):
            current_subset = str(a).strip()
            continue

        if isinstance(a, (int, float)) and not pd.isna(a):
            card_no = str(int(a))
            # b usually: "Player," ; c sometimes: Team or RC column depending on sheet formatting
            # From your sample, b=player, c=team, next col=RC.
            player = clean_player(str(b)) if not pd.isna(b) else ""
            team = str(c).strip() if not pd.isna(c) else ""
            rc = ""
            # try to find RC in any remaining cells
            for cell in row.iloc[2:6]:
                if isinstance(cell, str) and cell.strip().upper() == "RC":
                    rc = "RC"
            out[f"Base|{card_no}"] = {
                "checklist_type": "Base",
                "card_number": card_no,
                "subset": current_subset,
                "player": player,
                "team": team,
                "rc": rc,
            }
    return out

def parse_inserts_sheet(df: pd.DataFrame):
    # Expected columns: [<insert group name>, Unnamed: 1, Unnamed: 2]
    out = {}
    current_subset = str(df.columns[0]).strip() if df.columns.size else "Inserts"
    for _, row in df.iterrows():
        a = row.iloc[0] if len(row) > 0 else None
        b = row.iloc[1] if len(row) > 1 else None
        c = row.iloc[2] if len(row) > 2 else None

        if is_header_row(a, b, c):
            current_subset = str(a).strip()
            continue

        if is_code(a):
            code = str(a).strip()
            player = clean_player(str(b)) if not pd.isna(b) else ""
            team = str(c).strip() if not pd.isna(c) else ""
            out[f"Insert|{code.upper()}"] = {
                "checklist_type": "Insert",
                "card_number": code.upper(),
                "subset": current_subset,
                "player": player,
                "team": team,
                "rc": "",
            }
    return out

def parse_autos_sheet(df: pd.DataFrame):
    out = {}
    current_subset = str(df.columns[0]).strip() if df.columns.size else "Autographs"
    for _, row in df.iterrows():
        a = row.iloc[0] if len(row) > 0 else None
        b = row.iloc[1] if len(row) > 1 else None
        c = row.iloc[2] if len(row) > 2 else None

        if is_header_row(a, b, c):
            current_subset = str(a).strip()
            continue

        if isinstance(a, str) and "-" in a and a.strip():
            code = a.strip().upper()
            player = clean_player(str(b)) if not pd.isna(b) else ""
            team = str(c).strip() if not pd.isna(c) else ""
            out[f"Auto|{code}"] = {
                "checklist_type": "Auto",
                "card_number": code,
                "subset": current_subset,
                "player": player,
                "team": team,
                "rc": "",
            }
    return out

def extract_id_from_filename(name: str):
    # Handles:
    # Topps_Cosmic_2025_102_front.webp  -> ("Base|102", "front")
    # Topps_Cosmic_2025_ub-6_front.webp -> ("Insert|UB-6", "front")
    # ..._UB-4_..._front.webp           -> ("Insert|UB-4", "front")
    # ..._CCA-AR_..._front.webp         -> ("Auto|CCA-AR", "front")
    lower = name.lower()

    side = "front" if lower.endswith("_front.webp") else ("back" if lower.endswith("_back.webp") else None)
    if not side:
        return None, None

    # base number
    m = re.search(r"topps_cosmic_2025_(\d+)_", lower)
    if m:
        return f"Base|{int(m.group(1))}", side

    # code like UB-4 / LS-10 / CCA-AR etc anywhere
    m = re.search(r"\b([a-z]{1,6}-\d+)\b", lower)
    if m:
        code = m.group(1).upper()
        # heuristic: autos usually start with CCA-
        if code.startswith("CCA-"):
            return f"Auto|{code}", side
        return f"Insert|{code}", side

    # code like CCA-AR (letters after dash)
    m = re.search(r"\b(cca-[a-z]{1,4})\b", lower)
    if m:
        return f"Auto|{m.group(1).upper()}", side

    return None, side

def build_new_name(rec: dict, side: str, original_name: str):
    tags = []

    if rec.get("rc", "").upper() == "RC":
        tags.append("rc")

    ctype = (rec.get("checklist_type") or "").lower()
    subset = rec.get("subset") or ""

    if ctype == "base":
        tags.append("base")
    elif ctype == "insert":
        tags.append("insert-" + slug(subset))
    elif ctype == "auto":
        tags.append("auto")
        # keep subset label too if present
        if subset and subset.lower() not in ["autographs", ""]:
            tags.append("insert-" + slug(subset))

    # preserve numbered/parallel hints already embedded in old filenames
    # e.g. "..._150199_150of199_..."
    low = original_name.lower()
    m = re.search(r"(\d{2,3})of(\d{2,3})", low)
    if m:
        tags.append(f"numbered-{m.group(1)}of{m.group(2)}")

    player = slug(clean_player(rec.get("player", "")))
    team = slug(rec.get("team", ""))

    # fallback if checklist missing
    if player == "unknown" or team == "unknown":
        return None

    tag_part = "__".join(tags) if tags else "base"
    return f"{player}__{team}__{tag_part}__{SET_TAG}__{side}.webp"

def main():
    here = Path(__file__).resolve().parent
    checklist_path = here / "2025-Topps-Cosmic-Chrome-Baseball-Checklist.xlsx"
    if not checklist_path.exists():
        raise SystemExit(f"Missing checklist next to script: {checklist_path}")

    xl = pd.read_excel(checklist_path, sheet_name=None)

    lut = {}
    if "Full Checklist" in xl:
        lut.update(parse_full_checklist_base(xl["Full Checklist"]))
    if "Inserts" in xl:
        lut.update(parse_inserts_sheet(xl["Inserts"]))
    if "Autographs" in xl:
        lut.update(parse_autos_sheet(xl["Autographs"]))

    # folders to rename in-place
    targets = [
        here / "front-webp",
        here / "back-webp",
        here / "thumbs",
    ]

    # backup folder
    backup = here / "_backup_before_slug_rename"
    backup.mkdir(exist_ok=True)

    renamed = 0
    skipped = 0
    for folder in targets:
        if not folder.exists():
            continue
        for p in folder.glob("*.webp"):
            key, side = extract_id_from_filename(p.name)
            if not key or key not in lut:
                skipped += 1
                continue

            new_name = build_new_name(lut[key], side, p.name)
            if not new_name:
                skipped += 1
                continue

            dst = p.with_name(new_name)
            if dst.exists():
                # avoid clobber: add short suffix
                dst = p.with_name(dst.stem + "__dup" + dst.suffix)

            # backup original once
            shutil.copy2(p, backup / p.name)

            p.rename(dst)
            renamed += 1

    print(f"Renamed: {renamed}")
    print(f"Skipped (no match / already ok): {skipped}")
    print(f"Backup: {backup}")

if __name__ == "__main__":
    main()
