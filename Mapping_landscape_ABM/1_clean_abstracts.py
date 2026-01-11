# Veronika Wendler

from __future__ import annotations
from pathlib import Path
import csv
import re
import pandas as pd

INPUT_CSV = Path("Data/data.csv")
OUTPUT_CSV = Path("Data/data_cleaned_2.csv")


def normalize_text(x) -> str:
    if pd.isna(x):
        return x
    s = str(x)
    s = s.replace("\u00a0", " ")
    s = s.replace("Â©", "©") 
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    s = "\n".join(line.rstrip() for line in s.split("\n"))
    return s.strip()


def cut_at_first_copyright(s: str) -> str:
    """
    If '©' appears, cut everything from the first '©' onward.
    """
    if pd.isna(s):
        return s
    txt = str(s)
    idx = txt.find("©")
    return txt[:idx].strip() if idx != -1 else txt.strip()


# -----------------------------
# Main
def main() -> None:
    df = pd.read_csv(
        INPUT_CSV,
        sep=",",
        encoding="utf-8-sig",
        quotechar='"',
        on_bad_lines="warn",
    )

    df.columns = [str(c).strip() for c in df.columns]

    if "Abstract" not in df.columns:
        raise ValueError(
            f"'Abstract' column not found. Columns are: {list(df.columns)}"
        )

    df["Abstract"] = df["Abstract"].astype("string").str.replace(
        "31 patients aged ©60 years",
        "31 patients aged ⩾60 years",
        regex=False,
    )

    s = df["Abstract"].astype("string")
    s = s.map(normalize_text)
    s = s.map(cut_at_first_copyright)

    df["Abstract_cleaned"] = s
    df.to_csv(OUTPUT_CSV, index=False)

    print(f"Wrote cleaned dataset: {OUTPUT_CSV} (n={len(df)})")
    print("rows with copyright in cleaned:",
          df["Abstract_cleaned"].str.contains("©", na=False).sum())


if __name__ == "__main__":
    main()
    
