# code to randomly select 100 papers from the Scopus file

import pandas as pd
from pathlib import Path

in_path = Path(r"D:\Birmingham_Uni_Oct25\Papers\Mapping_Behav_RL\Mapping_landscape_ABM\Data\data_cleaned_2.csv")
out_path = in_path.parent / "data_rand_100_labels.csv"
df = pd.read_csv(in_path)

cols = ["id", "Abstract_cleaned"]

n = 100

df_sample = df.sample(n=n, replace=False, random_state=None)[cols]
df_sample.to_csv(out_path, index=False)
print(f"Saved {len(df_sample)} rows to: {out_path}")
