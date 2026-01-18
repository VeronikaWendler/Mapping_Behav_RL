import os
import requests
import concurrent.futures
import pandas as pd
import time
from functools import partial

with open("Mapping_landscape_ABM/Data/semantic_training/api.txt", "r") as f:
    url = f.readline().strip()
    auth = f.readline().strip()

headers = {"Authorization": auth, "Content-Type": "application/json"}

def run(system, user, timeout=90):
    payload = {
        "model": "gpt-4o-mini",
        "input": f"{system}\n\n{user}",
    }
    r = requests.post(url, headers=headers, json=payload, timeout=timeout)
    if r.status_code != 200:
        return f"ERROR status={r.status_code} body={r.text[:300]}"
    return r.json().get("output_text", "")

def run_parallel_map(system_prompt, users, workers=10):
    func = partial(run, system_prompt)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        return list(executor.map(func, users))

# Paths 
in_path = "Mapping_landscape_ABM/Data/semantic_training/train_pairs.csv"
out_path = "Mapping_landscape_ABM/Data/semantic_training/train_pairs_ratings.csv"

# load 
if os.path.exists(out_path):
    train = pd.read_csv(out_path)
else:
    train = pd.read_csv(in_path)
    train["out"] = ""

# Build prompts
pairs = [
    "-- Article 1 --\n" + i + "\n\n-- Article 2 --\n" + j
    for i, j in zip(train["text_i"].values, train["text_j"].values)
]

system_prompt = "You are an expert in the academic literature on behavioral agent-based modeling, who accurately discerns differences in specific research topics."

task_description = """Your primary task is to compare the following two articles (Article 1 and Article 2) based *only* on their provided titles and abstracts. Both articles operate within the general field of behavioral agent-based modeling (ABM).\n\nYour goal is to determine how similar their *specific research topics* are within the ABM context. Do they investigate the same sub-problem, mechanism, or research question?"""

format_instructions = """
First, provide your reasoning:
**Reasoning:**
[Provide a brief explanation here comparing the specific research topics, methodologies, or questions apparent in the titles/abstracts. Highlight similarities and differences relevant to the ABM field.]

Second, immediately following your reasoning, provide the numerical rating on a new line using the specified format.
Rate the similarity of the specific research topics on a scale from 0 to 100:
* **0:** Completely different specific research topics within ABM.
* **50:** The articles share significant common ground but ultimately address distinct specific research topics within ABM.
* **100:** The articles address the same specific research topic within ABM.

Strictly format the rating line *exactly* like this, with no extra text before or after:
Answer=[rating]"""

prompt_prefix = task_description + "\n\n"

final_user_prompts = [
    prompt_prefix + f"Here are the articles to evaluate:\n\n{pair}\n\n" + format_instructions
    for pair in pairs
]



# Find where to start to resume if it crashes
out_series = train["out"].fillna("").astype(str)
done_mask = (out_series.str.contains("Answer=")) | (out_series.str.len() > 0)

start_idx = int(done_mask.sum())  
# start_idx = int((~done_mask).idxmax()) if not done_mask.all() else len(train)

batch_size = 100
num_prompts = len(final_user_prompts)

print(f"Total prompts: {num_prompts}")
print(f"Already completed: {start_idx}")
print(f"Starting at index: {start_idx}")

for i in range(start_idx, num_prompts, batch_size):
    begin = i
    end = min(begin + batch_size, num_prompts)
    current_prompts = final_user_prompts[begin:end]

    start = time.time()
    batch_results = run_parallel_map(system_prompt, current_prompts, workers=10)

    train.iloc[begin:end, train.columns.get_loc("out")] = batch_results
    train.to_csv(out_path, index=False) 

    print(f"Batch {begin//batch_size + 1}: {begin}..{end-1} in {time.time()-start:.2f}s")
