# rewritten from the original authors: https://osf.io/preprints/psyarxiv/6c2va_v1

#libs
from __future__ import annotations
from pathlib import Path
import pandas as pd

INPUT_CSV = Path(r"Mapping_landscape_ABM/Data/scopus_export_Dec 29-2025_ABM.csv")
OUTPUT_CSV = Path("Data/data.csv")

REQUIRED_BASE = ["Title", "Abstract", "References", "Author(s) ID"]

def detect_delimiter(path: Path) -> str:
    header = path.read_text(encoding="utf-8-sig", errors="replace").splitlines()[0]
    counts = {
        "\t": header.count("\t"),
        ";": header.count(";"),
        ",": header.count(","),
    }
    delim = max(counts, key=counts.get)
    if counts[delim] == 0:
        raise ValueError(
            "Could not detect delimiter"
        )
    print(f"Detected delimiter: {repr(delim)} with counts {counts}")
    return delim

def main() -> None:
    OUTPUT_CSV.parent.mkdir(parents=True, exist_ok=True)

    sep = detect_delimiter(INPUT_CSV)

    df = pd.read_csv(
        INPUT_CSV,
        sep=sep,
        encoding="utf-8-sig",
        dtype=str,
        engine="python",
        on_bad_lines="warn",
    )

    # Drop empty columns 
    df = df.loc[:, ~df.columns.str.match(r"^Unnamed")].copy()
    df = df.loc[:, df.columns.astype(str).str.strip() != ""].copy()
    df.columns = [c.strip() for c in df.columns]

    if "Source" in df.columns:
        source_col = "Source"
    else:
        source_col = None

    required = REQUIRED_BASE + ([source_col] if source_col else [])
    missing = [c for c in required if c not in df.columns]
    if missing:
        raise ValueError(
            f"Available columns: {list(df.columns)}"
        )

    # Replace with NA
    df["Abstract"] = df["Abstract"].replace("[No abstract available]", pd.NA)

    # Stats
    n_entries = len(df)
    n_no_abs = df["Abstract"].isna().sum()
    n_no_refs = df["References"].isna().sum()
    n_no_auth = df["Author(s) ID"].isna().sum()

    if source_col:
        n_dupes = df.duplicated(subset=["Title", source_col]).sum()
    else:
        n_dupes = df.duplicated(subset=["Title"]).sum()

    print(f"Number of entries: {n_entries}")
    print(f"Entries without abstract: {n_no_abs}")
    print(f"Entries without references: {n_no_refs}")
    print(f"Entries with incomplete author info: {n_no_auth}")
    print(f"Duplicate entries (Title + {source_col or 'Title'}): {n_dupes}")

    df_f = df.dropna(subset=["Abstract", "References", "Author(s) ID"]).copy()
    if source_col:
        df_f = df_f.drop_duplicates(subset=["Title", source_col], keep="first").copy()
    else:
        df_f = df_f.drop_duplicates(subset=["Title"], keep="first").copy()

    df_f.insert(0, "id", range(1, len(df_f) + 1))
    df_f.to_csv(OUTPUT_CSV, index=False, encoding="utf-8")
    print(f"Wrote filtered dataset: {OUTPUT_CSV} (n={len(df_f)})")

if __name__ == "__main__":
    main()
