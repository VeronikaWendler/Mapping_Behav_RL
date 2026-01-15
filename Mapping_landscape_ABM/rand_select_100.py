# code which randomly selects 100 papers from the Scopus file

import pandas as pd
from pathlib import Path

in_path = Path(r"D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/data_cleaned_3.csv")
out_old = Path(r"D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/data_selected_labels_3.csv")
out_new = in_path.parent / "data_selected_labels_4.csv"

df_cleaned = pd.read_csv(in_path)
df_old = pd.read_csv(out_old)

cols = ["id", "Abstract_cleaned"]

n = 900
n_exclude = [3387,
                909,
                7994,
                3326,
                7451,
                8694,
                4815,
                5599,
                1643,
                6281,
                1824,
                3365,
                2217,
                5786,
                5002,
                6856,
                165,
                7274,
                8262,
                3514,
                2524,
                4875,
                5207,
                194,
                921,
                2977,
                5984,
                4659,
                1702,
                8567,
                3725,
                6880,
                588,
                5185,
                7604,
                2727,
                4128,
                2579,
                2265,
                5212,
                4887,
                275,
                4064,
                7111,
                69,
                5775,
                8378,
                4909,
                3653,
                80,
                4476,
                3246,
                2355,
                5379,
                2663,
                6139,
                3315,
                5225,
                1072,
                3283,
                359,
                1330,
                2846,
                1507,
                1949,
                3474,
                5773,
                5264,
                8472,
                4333,
                3765,
                4396,
                6892,
                3266,
                1619,
                6554,
                1879,
                6471,
                925,
                8109,
                6801,
                7465,
                2805,
                7049,
                4912,
                2015,
                7817,
                302,
                7744,
                4202,
                8701,
                831,
                7989,
                8125,
                6864,
                8387,
                6825,
                3090,
                5914,
                5588
                ]

df_cleaned = df_cleaned[~df_cleaned["id"].isin(n_exclude)]
df_sample = df_cleaned.sample(n=n, replace=False, random_state=None)[cols]

df_sample.rename(columns={'Abstract_cleaned': 'abstract'}, inplace=True)
df_stack = pd.concat([df_old, df_sample], axis=0)

df_stack.to_csv(out_new, index=False)
print(f"Saved {len(df_stack)} rows to: {out_new}")
