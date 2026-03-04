# import os
# import pandas as pd

# IN_PATH = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs.csv"
# OUT_PATH = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs_10k.csv"

# N = int(os.environ.get("SAMPLE_N", "10000"))
# SEED = int(os.environ.get("SAMPLE_SEED", "123"))

# MIN_CHARS = int(os.environ.get("MIN_CHARS", "10"))  # filter super-short rows

# df = pd.read_csv(IN_PATH)

# # Clean missing/empty
# def norm(x):
#     if pd.isna(x):
#         return ""
#     s = str(x).strip()
#     return "" if s.lower() == "nan" else s

# df["text_i"] = df["text_i"].apply(norm)
# df["text_j"] = df["text_j"].apply(norm)

# clean = df[
#     (df["text_i"].str.len() >= MIN_CHARS) &
#     (df["text_j"].str.len() >= MIN_CHARS)
# ].copy()

# print(f"Input rows: {len(df)}")
# print(f"Rows after non-empty/minlen filter: {len(clean)}")

# if len(clean) < N:
#     raise SystemExit(f"Not enough clean rows to sample N={N}. Only {len(clean)} available.")

# sample = clean.sample(n=N, random_state=SEED).reset_index(drop=True)
# sample.to_csv(OUT_PATH, index=False)

# print(f"Wrote sample: {OUT_PATH} (N={len(sample)}) seed={SEED} min_chars={MIN_CHARS}")


import pandas as pd

FULL_PATH = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs.csv"
USED_PATH = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs_10k.csv"

OUT_PATH = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training_1000/train_pairs_new_15k.csv"

N = 15000
SEED = 456

# load datasets
full = pd.read_csv(FULL_PATH)
used = pd.read_csv(USED_PATH)

print("Full dataset:", len(full))
print("Already used:", len(used))

# create unique pair key
full["pair_key"] = full["i"].astype(str) + "_" + full["j"].astype(str)
used["pair_key"] = used["i"].astype(str) + "_" + used["j"].astype(str)

# remove already used pairs
remaining = full[~full["pair_key"].isin(used["pair_key"])].copy()

print("Remaining pairs:", len(remaining))

# sample new pairs
sample = remaining.sample(n=N, random_state=SEED).reset_index(drop=True)

# drop helper column
sample = sample.drop(columns=["pair_key"])

# save
sample.to_csv(OUT_PATH, index=False)

print("Wrote:", OUT_PATH)
print("Rows:", len(sample))