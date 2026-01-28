# selecting the first 200 rows of the dataframe

import pandas as pd 
from pathlib import Path


in_path = Path(r"D:\Birmingham_Uni_Oct25\Papers\Mapping_Behav_RL\Mapping_landscape_ABM\Data\data_selected_labels_4.csv")
out_new = in_path.parent / "data_selected_labels_4_300.csv"

df = pd.read_csv(in_path)
df_200 = df.head(301)
df_200.to_csv(out_new, index=True)

