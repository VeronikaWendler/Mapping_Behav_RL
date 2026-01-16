
import pandas as pd
from pathlib import Path


in_path = Path(
    r"D:\Birmingham_Uni_Oct25\Papers\Mapping_Behav_RL\Mapping_landscape_ABM\Data\data_cleaned_2.csv"
)
out_path = in_path.parent / "data_selected_labels_2.csv"


ids = [
    3387, 909, 7994, 3326, 7451, 8694, 4815, 5599, 1643, 6281,
    1824, 3365, 2217, 5786, 5002, 6856, 165, 7274, 8262, 3514,
    2524, 4875, 5207, 194, 921, 2977, 5984, 4659, 1702, 8567,
    3725, 6880, 588, 5185, 7604, 2727, 4128, 2579, 2265, 5212,
    4887, 275, 4064, 7111, 69, 5775, 8378, 4909, 3653, 80,
    4476, 3246, 2355, 5379, 2663, 6139, 3315, 5225, 1072, 3283,
    359, 1330, 2846, 1507, 1949, 3474, 5773, 5264, 8472, 4333,
    3765, 4396, 6892, 3266, 1619, 6554, 1879, 6471, 925, 8109,
    6801, 7465, 2805, 7049, 4912, 2015, 7817, 302, 7744, 4202,
    8701, 831, 7989, 8125, 6864, 8387, 6825, 3090, 5914, 5588
]

df = pd.read_csv(in_path)
cols = ["id", "Abstract_cleaned"]
df_selected = df[df["id"].isin(ids)][cols]

df_selected["id"] = pd.Categorical(
    df_selected["id"], categories=ids, ordered=True
)
df_selected = df_selected.sort_values("id")

df_selected.to_csv(out_path, index=False)
print(f"Saved {len(df_selected)} rows to: {out_path}")

