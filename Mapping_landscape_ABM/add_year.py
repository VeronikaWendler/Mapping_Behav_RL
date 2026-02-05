import pandas as pd
import requests
import time
import re
from pathlib import Path

INPUT_CSV = r"D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/data_cleaned_filtered_4_300.csv"
OUTPUT_CSV = r"D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/data_cleaned_filtered_4_300_YE.csv"
CACHE_CSV = r"D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/data_cleaned_filtered_4_300_YE_cache.csv"

def norm_doi(x):
    if not isinstance(x, str):
        return None
    x = x.strip()
    if not x or x.lower() == "null":
        return None
    x = x.replace("https://doi.org/", "").replace("http://doi.org/", "")
    return x.strip().lower()

def get_year_crossref(doi, session):
    url = f"https://api.crossref.org/works/{doi}"
    r = session.get(url, timeout=30)
    if r.status_code == 404:
        return None
    r.raise_for_status()
    msg = r.json().get("message", {})

    for field in ["published-print", "published-online", "issued", "created"]:
        dp = msg.get(field, {}).get("date-parts")
        if dp and dp[0] and isinstance(dp[0][0], int):
            y = dp[0][0]
            if 1000 <= y <= 2100:
                return y
    return None

def fallback_year_from_abstract(text):
    if not isinstance(text, str):
        return None
    m = re.search(r"©\s*((19|20)\d{2})", text)
    return int(m.group(1)) if m else None

# 
try:
    df = pd.read_csv(INPUT_CSV, sep=";", dtype=str, keep_default_na=False, encoding="utf-8-sig")
    if "DOI" not in df.columns:
        df = pd.read_csv(INPUT_CSV, sep=",", dtype=str, keep_default_na=False, encoding="utf-8-sig")
except Exception:
    df = pd.read_csv(INPUT_CSV, sep=",", dtype=str, keep_default_na=False, encoding="utf-8-sig")

if "DOI" not in df.columns:
    raise ValueError(f"Couldn't find a DOI column. Columns are: {list(df.columns)[:30]} ...")

# preserve original row order explicitly
df["_orig_row"] = range(len(df))

# normalize DOI
df["DOI_norm"] = df["DOI"].apply(norm_doi)

cache_path = Path(CACHE_CSV)
doi_to_year = {}

if cache_path.exists():
    cache_df = pd.read_csv(cache_path, dtype=str)
    # DOI_norm, Year
    if "DOI_norm" in cache_df.columns and "Year" in cache_df.columns:
        # keep as int where possible
        tmp = cache_df.dropna(subset=["DOI_norm", "Year"])
        doi_to_year = dict(zip(tmp["DOI_norm"], tmp["Year"].astype(int)))

missing = [d for d in df["DOI_norm"].dropna().unique() if d not in doi_to_year]

session = requests.Session()
session.headers.update({
    "User-Agent": "ScopusYearEnricher/1.0 (mailto:your-email@example.com)"
})

for i, doi in enumerate(missing, start=1):
    try:
        y = get_year_crossref(doi, session)
        if y is not None:
            doi_to_year[doi] = y
    except Exception:
        pass

    # save progress every 500 DOIs
    if i % 500 == 0:
        tmp_cache = pd.DataFrame(list(doi_to_year.items()), columns=["DOI_norm", "Year"])
        tmp_cache.to_csv(CACHE_CSV, index=False)
        print(f"Saved cache at {i}/{len(missing)} DOIs...")

    time.sleep(0.12)  # rate limiting

pd.DataFrame(list(doi_to_year.items()), columns=["DOI_norm", "Year"]).to_csv(CACHE_CSV, index=False)
df["Year"] = df["DOI_norm"].map(doi_to_year)
if "Abstract" in df.columns:
    mask = df["Year"].isna()
    df.loc[mask, "Year"] = df.loc[mask, "Abstract"].apply(fallback_year_from_abstract)

# safety check
assert (df["_orig_row"].values == range(len(df))).all()

df.drop(columns=["DOI_norm"]).to_csv(OUTPUT_CSV, index=False)
print("Done:", OUTPUT_CSV)
print("Total rows:", len(df))
print("Rows with Year filled:", df["Year"].notna().sum())
print("Rows missing Year:", df["Year"].isna().sum())
