from __future__ import annotations

from pathlib import Path
import csv
import re
import pandas as pd

INPUT_CSV = Path("Data/data.csv")
OUTPUT_CSV = Path("Data/data_cleaned.csv")


# -----------------------------
# CSV delimiter detection
def sniff_delimiter(path: Path, sample_lines: int = 30) -> str:
    lines: list[str] = []
    with path.open("r", encoding="utf-8-sig", errors="replace", newline="") as f:
        for _ in range(sample_lines):
            line = f.readline()
            if not line:
                break
            if line.strip():
                lines.append(line)

    if not lines:
        raise ValueError("Input file seems empty.")

    sample = "".join(lines)

    try:
        dialect = csv.Sniffer().sniff(sample, delimiters=["\t", ";", ",", "|"])
        return dialect.delimiter
    except Exception:
        header = lines[0]
        counts = {d: header.count(d) for d in ["\t", ";", ",", "|"]}
        return max(counts, key=counts.get)


# -----------------------------
# Text helpers
def normalize_text(x) -> str:
    if pd.isna(x):
        return x
    s = str(x)
    s = s.replace("\u00a0", " ")
    s = s.replace("Â©", "©")  
    s = s.replace("\r\n", "\n").replace("\r", "\n")
    s = "\n".join(line.rstrip() for line in s.split("\n"))
    return s.strip()


EMAIL_RE = re.compile(r"\b[\w.\-+%]+@[\w.\-]+\.[A-Za-z]{2,}\b", flags=re.IGNORECASE)

BAD_MARKERS_RE = re.compile(
    r"(?is)\n?\s*("
    r"from\s+__future__\s+import|"
    r"import\s+pandas|"
    r"import\s+re|"
    r"import\s+csv|"
    r"from\s+pathlib\s+import|"
    r"def\s+\w+\s*\(|"
    r"if\s+__name__\s*==\s*[\"']__main__[\"']"
    r")"
)

JUNK_MARKER_RE = re.compile(
    r"""
    (                           
        @                       
        |
        ©                       
        |
        \(c\)                 
        |
        \bcopyright\b           
        |
        \ball\s+rights\s+reserved\b
        |
        \btext\s+and\s+data\s+mining\b
        |
        \bai\s+training\b
        |
        \bcreative\s+commons\b
        |
        \bcc\s*by(?:[-\s]?(?:nc|nd|sa))?\b
        |
        \bopen\s+access\b
        |
        \blicen[cs]e(?:e|d)?\b
        |
        \bunder\s+(?:exclusive\s+)?licen[cs]e\b
        |
        \bpublished\s+by\b
        |
        \bthe\s+author(?:s)?\b
        |
        \belsevier\b
        |
        \bspringer(?:\s+nature)?\b
        |
        \bwiley\b
        |
        \btaylor\s*&\s*francis\b
        |
        \bamerican\s+society\s+of\s+civil\s+engineers\b
        |
        \bt&f\b
    )
    """,
    flags=re.IGNORECASE | re.DOTALL | re.VERBOSE,
)

TAIL_GARBAGE_RE = re.compile(r"(?s)[\s@#|;:,_\-–—]{3,}\s*$")


def truncate_at_bad_marker(s: str) -> str:
    if pd.isna(s):
        return s
    txt = str(s)
    m = BAD_MARKERS_RE.search(txt)
    return txt[: m.start()].strip() if m else txt.strip()


def truncate_at_email(s: str) -> str:

    if pd.isna(s):
        return s
    txt = str(s)
    m = EMAIL_RE.search(txt)
    return txt[: m.start()].strip() if m else txt.strip()


def hard_cut_at_first_junk_marker(s: str) -> str:
    """
    - cut everything from the FIRST '@' onward
    - cut everything from the FIRST copyright/licence/publisher marker onward (incl. '©')
    """
    if pd.isna(s):
        return s
    txt = str(s).strip()
    if not txt:
        return txt

    m = JUNK_MARKER_RE.search(txt)
    if m:
        txt = txt[: m.start()].strip()

    if "@" in txt:
        txt = txt.split("@", 1)[0].strip()
    if "©" in txt:
        txt = txt.split("©", 1)[0].strip()

    return txt


def strip_tail_garbage(s: str) -> str:
    if pd.isna(s):
        return s
    return TAIL_GARBAGE_RE.sub("", str(s)).strip()


# -----------------------------
# Main
def main() -> None:
    delim = sniff_delimiter(INPUT_CSV)
    print(f"Detected delimiter: {repr(delim)}")

    df = pd.read_csv(
        INPUT_CSV,
        sep=delim,
        engine="python",
        encoding="utf-8-sig",
        quotechar='"',
        on_bad_lines="warn",
    )

    df.columns = [str(c).strip() for c in df.columns]

    if "Abstract" not in df.columns:
        raise ValueError(
            "Input file is missing 'Abstract' column.\n"
            f"Detected delimiter: {repr(delim)}\n"
            f"Available columns: {list(df.columns)}"
        )

    df["Abstract"] = df["Abstract"].astype("string").str.replace(
        "31 patients aged ©60 years",
        "31 patients aged ⩾60 years",
        regex=False,
    )

    s = df["Abstract"].astype("string")
    s = s.map(normalize_text)
    s = s.map(truncate_at_bad_marker)
    s = s.map(truncate_at_email)
    s = s.map(hard_cut_at_first_junk_marker)  
    s = s.map(strip_tail_garbage)

    df["Abstract_cleaned"] = s
    df.to_csv(OUTPUT_CSV, index=False)

    # Diagnostics
    print(f"Wrote cleaned dataset: {OUTPUT_CSV} (n={len(df)})")
    print("rows with ANY @ in cleaned:", df["Abstract_cleaned"].str.contains("@", na=False).sum())
    print("rows with ANY © in cleaned:", df["Abstract_cleaned"].str.contains("©", na=False).sum())
    print("rows with Elsevier in cleaned:", df["Abstract_cleaned"].str.contains("Elsevier", case=False, na=False).sum())
    print("emails still present (cleaned):", df["Abstract_cleaned"].str.contains(EMAIL_RE, na=False).sum())

    # show any failures (should be 0)
    bad = df.loc[df["Abstract_cleaned"].str.contains(r"@|©", na=False), "Abstract_cleaned"].head(5)
    if len(bad) > 0:
        print("\nExamples STILL containing @ or © (last 400 chars):")
        for i, t in enumerate(bad.tolist(), 1):
            print(f"\n--- bad {i} ---\n{t[-400:]}")


if __name__ == "__main__":
    main()
