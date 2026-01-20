import os
import time
import random
import re
import requests
import concurrent.futures
import pandas as pd
from functools import partial

# ----------------------------
# CONFIG (pilot)
# ----------------------------
PILOT_N = 50      
BATCH_SIZE = 10
WORKERS = 2
TIMEOUT = 120
MAX_RETRIES = 6

MODEL = "meta-llama/Llama-3.3-70B-Instruct" 
MAX_TOKENS = 10
TEMPERATURE = 0.0

ANSWER_RE = re.compile(r"Answer\s*=\s*(\d{1,3})")


API_PATH = "Mapping_landscape_ABM/Data/semantic_training/api.txt"
with open(API_PATH, "r") as f:
    url = f.readline().strip()
    auth = f.readline().strip()

headers = {"Authorization": auth, "Content-Type": "application/json"}

# ----------------------------
# Request function
# ----------------------------
def run(system, user, timeout=TIMEOUT, max_retries=MAX_RETRIES):
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "max_tokens": MAX_TOKENS,
        "temperature": TEMPERATURE,
    }

    for attempt in range(max_retries):
        try:
            r = requests.post(url, headers=headers, json=payload, timeout=timeout)

            if r.status_code == 200:
                j = r.json()
                txt = j["choices"][0]["message"]["content"]
                return txt.strip()

            # transient
            if r.status_code in (408, 429, 500, 502, 503, 504):
                time.sleep(min(60, (2 ** attempt) + random.random()))
                continue

            # non-transient: auth/billing/access/model not found
            return f"ERROR status={r.status_code} body={r.text[:300]}"

        except requests.exceptions.Timeout:
            time.sleep(min(60, (2 ** attempt) + random.random()))
            continue
        except Exception as e:
            return f"ERROR exception={type(e).__name__} msg={str(e)[:200]}"

    return "ERROR max_retries_exceeded"


def run_parallel(system_prompt, users):
    func = partial(run, system_prompt)
    results = [None] * len(users)
    with concurrent.futures.ThreadPoolExecutor(max_workers=WORKERS) as ex:
        futs = {ex.submit(func, u): i for i, u in enumerate(users)}
        for fut in concurrent.futures.as_completed(futs):
            i = futs[fut]
            try:
                results[i] = fut.result()
            except Exception as e:
                results[i] = f"ERROR exception={repr(e)}"
    return results


# ----------------------------
# Paths
in_path = "Mapping_landscape_ABM/Data/semantic_training/train_pairs.csv"
out_path = "Mapping_landscape_ABM/Data/semantic_training/train_pairs_ratings.csv"

# load
if os.path.exists(out_path):
    train = pd.read_csv(out_path)
    if "out" not in train.columns:
        train["out"] = ""
else:
    train = pd.read_csv(in_path)
    train["out"] = ""

out_series = train["out"].fillna("").astype(str)
done_mask = out_series.str.contains(r"Answer\s*=", regex=True)

not_done_idx = train.index[~done_mask]
start_idx = int(not_done_idx.min()) if len(not_done_idx) else len(train)

end_total = min(len(train), start_idx + PILOT_N)

print(f"Total rows in train_pairs: {len(train)}")
print(f"Already completed (Answer=): {int(done_mask.sum())}")
print(f"Pilot will run rows: {start_idx}..{end_total-1} (N={end_total-start_idx})")


system_prompt = (
    "You are an expert in the academic literature on agent-based modeling (ABM). "
    "Return ONLY a single line exactly in the format Answer=NN where NN is an integer 0-100."
)

task_description = (
    "Compare Article 1 and Article 2 based only on title and abstract. "
    "Rate similarity of their specific ABM research topic from 0 (completely different) "
    "to 100 (same topic). Return ONLY: Answer=NN"
)

pairs = [
    "-- Article 1 --\n" + str(i) + "\n\n-- Article 2 --\n" + str(j)
    for i, j in zip(train["text_i"].values, train["text_j"].values)
]

prompts = [f"{task_description}\n\n{pair}\n\nReturn ONLY: Answer=NN" for pair in pairs]



print("\nSMOKE TEST...")
smoke = run(system_prompt, "Return ONLY: Answer=7")
print("SMOKE OUT:", smoke)
if not ANSWER_RE.search(smoke or ""):
    print("Smoke test did not return Answer=NN. Check billing/access/model/provider.")


for begin in range(start_idx, end_total, BATCH_SIZE):
    end = min(begin + BATCH_SIZE, end_total)
    current_prompts = prompts[begin:end]

    t0 = time.time()
    batch_out = run_parallel(system_prompt, current_prompts)

    cleaned = []
    for x in batch_out:
        m = ANSWER_RE.search(x or "")
        if m:
            nn = int(m.group(1))
            nn = max(0, min(100, nn))
            cleaned.append(f"Answer={nn}")
        else:
            cleaned.append(x if x else "ERROR empty")

    train.iloc[begin:end, train.columns.get_loc("out")] = cleaned
    train.to_csv(out_path, index=False)

    n_ans = sum(bool(ANSWER_RE.search(x or "")) for x in cleaned)
    n_err = sum((x or "").startswith("ERROR") for x in cleaned)
    print(f"Batch {begin//BATCH_SIZE + 1}: {begin}..{end-1} in {time.time()-t0:.1f}s | OK={n_ans}/{len(cleaned)} | ERR={n_err}")
