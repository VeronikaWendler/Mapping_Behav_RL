import os
import time
import random
import requests
import concurrent.futures
import pandas as pd
from functools import partial

# ----------------------------
# read hidden api
with open("Mapping_landscape_ABM/Data/semantic_training/api.txt", "r") as f:
    url = f.readline().strip()
    auth = f.readline().strip()

headers = {"Authorization": auth, "Content-Type": "application/json"}

MODEL = "meta-llama/llama-3.3-70b-instruct"

def run(system, user, timeout=120, max_retries=6):
    """One request with retry/backoff. Returns model text or an ERROR string."""
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
    }

    for attempt in range(max_retries):
        try:
            r = requests.post(url, headers=headers, json=payload, timeout=timeout)

            # Success
            if r.status_code == 200:
                j = r.json()
                return j["choices"][0]["message"]["content"]

            # Common transient failures (rate limits / overload)
            if r.status_code in (429, 500, 502, 503, 504):
                sleep_s = min(60, (2 ** attempt) + random.random())
                time.sleep(sleep_s)
                continue

            # Other errors: keep the body for debugging
            return f"ERROR status={r.status_code} body={r.text[:300]}"

        except requests.exceptions.Timeout:
            sleep_s = min(60, (2 ** attempt) + random.random())
            time.sleep(sleep_s)
            continue
        except Exception as e:
            return f"ERROR exception={type(e).__name__} msg={str(e)[:200]}"

    return "ERROR max_retries_exceeded"

def run_parallel_map(system_prompt, users, workers=5):
    func = partial(run, system_prompt)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as ex:
        return list(ex.map(func, users))

# ----------------------------
# Paths
# ----------------------------
in_path = "Mapping_landscape_ABM/Data/semantic_training/train_pairs.csv"
out_path = "Mapping_landscape_ABM/Data/semantic_training/train_pairs_ratings.csv"

# Load existing progress if present
if os.path.exists(out_path):
    train = pd.read_csv(out_path)
    if "out" not in train.columns:
        train["out"] = ""
else:
    train = pd.read_csv(in_path)
    train["out"] = ""

pairs = ["-- Article 1 --\n" + i + "\n\n-- Article 2 --\n" + j for i, j in zip(train["text_i"].values, train["text_j"].values)]

system_prompt = "You are an expert in the academic literature on behavioral reinforcement learning, who accurately discerns differences in specific research topics."
task_description = """Your primary task is to compare the following two articles (Article 1 and Article 2) based *only* on their provided titles and abstracts. Both articles operate within the general field of behavioral reinforcement learning (BRL).\n\nYour goal is to determine how similar their *specific research topics* are within the BRL context. Do they investigate the same sub-problem, mechanism, or research question?"""
format_instructions = """
First, provide your reasoning:
**Reasoning:**
[Provide a brief explanation here comparing the specific research topics, methodologies, or questions apparent in the titles/abstracts. Highlight similarities and differences relevant to the BRL field.]

Second, immediately following your reasoning, provide the numerical rating on a new line using the specified format.
Rate the similarity of the specific research topics on a scale from 0 to 100:
* **0:** Completely different specific research topics within BRL.
* **50:** The articles share significant common ground but ultimately address distinct specific research topics within BRL.
* **100:** The articles address the same specific research topic within BRL.

Strictly format the rating line *exactly* like this, with no extra text before or after:
Answer=[rating]"""

prompt_prefix = task_description + "\n\n"
final_user_prompts = [
    prompt_prefix + f"Here are the articles to evaluate:\n\n{pair}\n\n" + format_instructions
    for pair in pairs
]

# ----------------------------
# Resume logic: only Answer= counts as done
# ----------------------------
out_series = train["out"].fillna("").astype(str)
done_mask = out_series.str.contains("Answer=")

# Start at first not-done index (not "count of non-empty")
not_done_idx = train.index[~done_mask]
start_idx = int(not_done_idx.min()) if len(not_done_idx) else len(train)

batch_size = 100
num_prompts = len(final_user_prompts)

print(f"Total prompts: {num_prompts}")
print(f"Already completed (Answer=): {done_mask.sum()}")
print(f"Starting at index: {start_idx}")

# ----------------------------
# Main loop
# ----------------------------
for i in range(start_idx, num_prompts, batch_size):
    begin = i
    end = min(begin + batch_size, num_prompts)
    current_prompts = final_user_prompts[begin:end]

    t0 = time.time()
    batch_results = run_parallel_map(system_prompt, current_prompts, workers=5)

    train.iloc[begin:end, train.columns.get_loc("out")] = batch_results
    train.to_csv(out_path, index=False)

    dt = time.time() - t0
    print(f"Batch {begin//batch_size + 1}: {begin}..{end-1} in {dt:.2f}s")