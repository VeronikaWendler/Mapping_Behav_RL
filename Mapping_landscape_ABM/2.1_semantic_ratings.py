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
in_path = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training/train_pairs.csv"
out_path = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training/train_pairs_ratings.csv"

# Load existing progress if present
if os.path.exists(out_path):
    train = pd.read_csv(out_path)
    if "out" not in train.columns:
        train["out"] = ""
else:
    train = pd.read_csv(in_path)
    train["out"] = ""

pairs = ["-- Article 1 --\n" + i + "\n\n-- Article 2 --\n" + j for i, j in zip(train["text_i"].values, train["text_j"].values)]

system_prompt = "You are an expert in the academic literature on behavioral agent-based modeling (ABM), who accurately discerns differences in specific research topics."
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









# import os
# import time
# import random
# import re
# import requests
# import concurrent.futures
# import pandas as pd
# from functools import partial


# PILOT_N = 500      
# BATCH_SIZE = 10
# WORKERS = 2
# TIMEOUT = 120
# MAX_RETRIES = 6

# MODEL = "meta-llama/Llama-3.3-70B-Instruct"
# MAX_TOKENS = 10
# TEMPERATURE = 0.0

# ANSWER_RE = re.compile(r"Answer\s*=\s*(\d{1,3})")


# API_PATH = "Mapping_landscape_ABM/Data/semantic_training/api.txt"
# with open(API_PATH, "r") as f:
#     url = f.readline().strip()
#     auth = f.readline().strip()

# headers = {"Authorization": auth, "Content-Type": "application/json"}

# # ----------------------------

# def run(system, user, timeout=TIMEOUT, max_retries=MAX_RETRIES):
#     payload = {
#         "model": MODEL,
#         "messages": [
#             {"role": "system", "content": system},
#             {"role": "user", "content": user},
#         ],
#         "max_tokens": MAX_TOKENS,
#         "temperature": TEMPERATURE,
#     }

#     for attempt in range(max_retries):
#         try:
#             r = requests.post(url, headers=headers, json=payload, timeout=timeout)

#             if r.status_code == 200:
#                 j = r.json()
#                 txt = j["choices"][0]["message"]["content"]
#                 return txt.strip()

#             # transient
#             if r.status_code in (408, 429, 500, 502, 503, 504):
#                 time.sleep(min(60, (2 ** attempt) + random.random()))
#                 continue

#             # non-transient: auth/billing/access/model not found
#             return f"ERROR status={r.status_code} body={r.text[:300]}"

#         except requests.exceptions.Timeout:
#             time.sleep(min(60, (2 ** attempt) + random.random()))
#             continue
#         except Exception as e:
#             return f"ERROR exception={type(e).__name__} msg={str(e)[:200]}"

#     return "ERROR max_retries_exceeded"


# def run_parallel(system_prompt, users):
#     func = partial(run, system_prompt)
#     results = [None] * len(users)
#     with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as ex:
#         futs = {ex.submit(func, u): i for i, u in enumerate(users)}
#         for fut in concurrent.futures.as_completed(futs):
#             i = futs[fut]
#             try:
#                 results[i] = fut.result()
#             except Exception as e:
#                 results[i] = f"ERROR exception={repr(e)}"
#     return results


# # ----------------------------
# # Paths
# in_path = "Mapping_landscape_ABM/Data/semantic_training/train_pairs.csv"
# out_path = "Mapping_landscape_ABM/Data/semantic_training/train_pairs_ratings.csv"

# # load
# if os.path.exists(out_path):
#     train = pd.read_csv(out_path)
#     if "out" not in train.columns:
#         train["out"] = ""
# else:
#     train = pd.read_csv(in_path)
#     train["out"] = ""

# out_series = train["out"].fillna("").astype(str)
# done_mask = out_series.str.contains(r"Answer\s*=", regex=True)

# not_done_idx = train.index[~done_mask]
# start_idx = int(not_done_idx.min()) if len(not_done_idx) else len(train)

# end_total = min(len(train), start_idx + PILOT_N)

# print(f"Total rows in train_pairs: {len(train)}")
# print(f"Already completed (Answer=): {int(done_mask.sum())}")
# print(f"Pilot will run rows: {start_idx}..{end_total-1} (N={end_total-start_idx})")


# system_prompt = (
#     "You are an expert in the academic literature on agent-based modeling (ABM). "
#     "Return ONLY a single line exactly in the format Answer=NN where NN is an integer 0-100."
# )

# task_description = (
#     "Compare Article 1 and Article 2 based only on title and abstract. "
#     "Rate similarity of their specific ABM research topic from 0 (completely different) "
#     "to 100 (same topic). Return ONLY: Answer=NN"
# )

# sub = train.iloc[start_idx:end_total]

# pairs = [
#     "-- Article 1 --\n" + str(i) + "\n\n-- Article 2 --\n" + str(j)
#     for i, j in zip(sub["text_i"].values, sub["text_j"].values)
# ]
# prompts = [f"{task_description}\n\n{pair}\n\nReturn ONLY: Answer=NN" for pair in pairs]


# print("\nSMOKE TEST...")
# smoke = run(system_prompt, "Return ONLY: Answer=7")
# print("SMOKE OUT:", smoke)
# if not ANSWER_RE.search(smoke or ""):
#     raise SystemExit("Smoke test failed (no Answer=NN). Not running pilot.")



# for begin in range(start_idx, end_total, BATCH_SIZE):
#     end = min(begin + BATCH_SIZE, end_total)
#     current_prompts = prompts[begin - start_idx : end - start_idx]

#     t0 = time.time()
#     batch_out = run_parallel(system_prompt, current_prompts)

#     cleaned = []
#     for x in batch_out:
#         m = ANSWER_RE.search(x or "")
#         if m:
#             nn = int(m.group(1))
#             nn = max(0, min(100, nn))
#             cleaned.append(f"Answer={nn}")
#         else:
#             cleaned.append(x if x else "ERROR empty")

#     train.iloc[begin:end, train.columns.get_loc("out")] = cleaned
#     train.to_csv(out_path, index=False)

#     n_ans = sum(bool(ANSWER_RE.search(x or "")) for x in cleaned)
#     n_err = sum((x or "").startswith("ERROR") for x in cleaned)
#     print(f"Batch {begin//BATCH_SIZE + 1}: {begin}..{end-1} in {time.time()-t0:.1f}s | OK={n_ans}/{len(cleaned)} | ERR={n_err}")
