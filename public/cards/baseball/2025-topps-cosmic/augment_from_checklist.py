#!/usr/bin/env python3
"""
augment_from_checklist.py

Auto-fills cards_metadata_template.csv with player/team/subset (and rookie flag)
using checklist_lookup.csv.

Fixes included:
- Handles duplicate checklist keys (checklist_type + card_number) by preferring rows
  where rc_flag == "RC" when duplicates exist.
- Avoids PermissionError on Windows by NOT writing a duplicates report unless requested.

Usage:
  python augment_from_checklist.py --csv cards_metadata_template.csv --checklist checklist_lookup.csv --out cards_metadata_enriched.csv

Optional:
  python augment_from_checklist.py --csv ... --checklist ... --out ... --write-dups --dups-out dups.csv
"""

import argparse
from pathlib import Path
import pandas as pd


def norm(value) -> str:
    if value is None:
        return ""
    return str(value).strip()


def maybe_set(row, column: str, value: str):
    """Only set row[column] if it's blank and value is non-blank."""
    if not norm(row.get(column, "")) and norm(value):
        row[column] = value
    return row


def safe_write_csv(df: pd.DataFrame, path: Path):
    """Write CSV but do not crash if the file is locked/open (e.g., Excel)."""
    try:
        df.to_csv(path, index=False)
        print(f"NOTE: Wrote duplicates report: {path}")
    except PermissionError:
        print(f"WARNING: Permission denied writing: {path}")
        print("         Close Excel or choose a different --dups-out path.")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--csv", required=True, help="Cards metadata CSV (template).")
    parser.add_argument("--checklist", required=True, help="Checklist lookup CSV.")
    parser.add_argument("--out", required=True, help="Output enriched CSV.")
    parser.add_argument(
        "--rc-token",
        default="rookie",
        help="Token appended to other_desc when rc_flag == RC (default: rookie).",
    )
    parser.add_argument(
        "--write-dups",
        action="store_true",
        help="Write a duplicates report CSV (disabled by default).",
    )
    parser.add_argument(
        "--dups-out",
        default="checklist_duplicates.csv",
        help="Duplicates report filename/path (default: checklist_duplicates.csv).",
    )
    args = parser.parse_args()

    cards = pd.read_csv(args.csv, dtype=str).fillna("")
    chk = pd.read_csv(args.checklist, dtype=str).fillna("")

    # Ensure expected columns exist (in case checklist format varies)
    for col in ["checklist_type", "card_number", "subset", "player_name", "team", "rc_flag"]:
        if col not in chk.columns:
            chk[col] = ""

    # Build unique key
    chk["checklist_type"] = chk["checklist_type"].astype(str).str.strip()
    chk["card_number"] = chk["card_number"].astype(str).str.strip()
    chk["rc_flag"] = chk["rc_flag"].astype(str).fillna("").str.strip()
    chk["key"] = chk["checklist_type"] + "|" + chk["card_number"]

    # Detect duplicates
    dup_mask = chk.duplicated("key", keep=False)
    dups = chk.loc[dup_mask].copy()

    if not dups.empty:
        print(f"NOTE: Duplicate checklist keys detected: {dups['key'].nunique()} keys duplicated.")
        print("      Script will prefer rows where rc_flag == RC.")

    # Optionally write duplicates report
    if args.write_dups and not dups.empty:
        cols = [c for c in ["checklist_type", "card_number", "subset", "player_name", "team", "rc_flag", "key"] if c in dups.columns]
        report = dups[cols].sort_values(["key", "rc_flag"], ascending=[True, False])
        safe_write_csv(report, Path(args.dups_out))

    # Prefer RC rows when duplicates exist
    chk["_rc_rank"] = (chk["rc_flag"].str.upper() == "RC").astype(int)
    chk_dedup = (
        chk.sort_values(["key", "_rc_rank"], ascending=[True, False])
           .drop_duplicates("key", keep="first")
           .drop(columns=["_rc_rank"])
    )

    # Build lookup dict
    lut = chk_dedup.set_index("key").to_dict(orient="index")

    # Ensure cards columns exist
    for col in ["checklist_type", "card_number", "player_name", "team", "subset", "other_desc"]:
        if col not in cards.columns:
            cards[col] = ""

    enriched_rows = []
    for _, r in cards.iterrows():
        ctype = norm(r.get("checklist_type", ""))
        cnum = norm(r.get("card_number", ""))
        key = f"{ctype}|{cnum}" if ctype and cnum else ""

        if key and key in lut:
            rec = lut[key]
            r = maybe_set(r, "player_name", rec.get("player_name", ""))
            r = maybe_set(r, "team", rec.get("team", ""))
            r = maybe_set(r, "subset", rec.get("subset", ""))

            # RC flag -> other_desc token
            if norm(rec.get("rc_flag", "")).upper() == "RC":
                token = norm(args.rc_token)
                if token:
                    od = norm(r.get("other_desc", ""))
                    if token.lower() not in od.lower():
                        r["other_desc"] = (od + (" " if od else "") + token).strip()

        enriched_rows.append(r)

    out_df = pd.DataFrame(enriched_rows)
    out_df.to_csv(args.out, index=False)
    print(f"Wrote: {args.out}")


if __name__ == "__main__":
    main()
