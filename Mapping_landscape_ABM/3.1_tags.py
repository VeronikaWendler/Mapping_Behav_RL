import requests
import concurrent.futures
import pandas as pd
import time
import random
from functools import partial

# ---- read api.txt (2 lines: url, "Bearer hf_...") ----
with open("Mapping_landscape_ABM/Data/semantic_training/api.txt", "r") as f:
    api = f.readlines()

url = api[0].strip()       
auth = api[1].strip()      

headers = {
    "Authorization": auth,
    "Content-Type": "application/json"
}

MODEL = "meta-llama/Llama-3.3-70B-Instruct"  

def run(system, user, timeout=120, max_retries=6):
    payload = {
        "model": MODEL,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user}
        ],
        "max_tokens": 500,
        "temperature": 0.0
    }

    for attempt in range(max_retries):
        try:
            r = requests.post(url, headers=headers, json=payload, timeout=timeout)

            if r.status_code == 200:
                j = r.json()
                return j["choices"][0]["message"]["content"]

            if r.status_code in (408, 429, 500, 502, 503, 504):
                time.sleep(min(60, (2 ** attempt) + random.random()))
                continue

            # non-transient: show body for debugging
            return f"ERROR status={r.status_code} body={r.text[:300]}"

        except requests.exceptions.Timeout:
            time.sleep(min(60, (2 ** attempt) + random.random()))
            continue
        except Exception as e:
            return f"ERROR exception={type(e).__name__} msg={str(e)[:200]}"

    return "ERROR max_retries_exceeded"


def run_parallel_map(system_prompt, users, workers=10):
    func = partial(run, system_prompt)
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        results = list(executor.map(func, users))
    return results


data = pd.read_csv("Mapping_landscape_ABM/Data/data_cleaned_filtered_4_200.csv")
data["text"] = "Title: " + data["Title"].astype(str).values + ".\nAbstract: " + data["Abstract_cleaned"].astype(str).values

system_prompt = (
    "You are an expert research assistant specializing in behavioral agent-based modeling.\n"
    "You analyze academic papers to generate precise, contextually relevant taxonomic tags.\n"
)

task_description = (
  "Analyze the provided Title and Abstract to generate precise taxonomic tags characterizing the paper's core **subject** and **methodology**. Your main task is to balance **concept normalization** with **verbatim extraction**.\n"
  "\n"
  "**Tagging Principles:**\n"
  "1.  **Normalize Common Terms:** For standard concepts, methods, or abbreviations, consolidate them into a single, canonical tag.\n"
  "2.  **Preserve Specific Phrases:** For unique or highly specific conceptual phrases that define a core idea, you MUST extract them verbatim to preserve their precise meaning.\n"
  "\n"
  "**General Guidelines:**\n"
  "1. Generate between 3 and 7 distinct, non-redundant tags.\n"
  "2. Ensure a balance between subject and methodology.\n"
  "3. Tags should be concise (ideally 1-3 words), but a specific verbatim phrase may be longer if necessary.\n"
)

output_format_instructions = (
    "**Output Structure:**\n"
    "1. **Reasoning (Brief):** First, provide a concise explanation of your tagging choices.\n"
    "2. **Taxonomic Tags:** Immediately following your reasoning, provide the taxonomic tags.\n"
    "They must be separated by a semicolon (;) and enclosed within 'Answer=[...]'.\n\n"
    "**Strict Formatting Example for Tags:**\n"
    "Answer=[tags]"
)

final_user_prompts = []
for text_content in data["text"].values:
    prompt = (
        f"{task_description}\n\n"
        f"**Article to evaluate:**\n{text_content}\n\n"
        f"{output_format_instructions}"
    )
    final_user_prompts.append(prompt)

# Optional: smoke test (highly recommended on cluster)
print("SMOKE TEST:", run(system_prompt, "Return ONLY: Answer=[test]"))

tags = pd.DataFrame({"id": data["id"].values})
tags["out"] = ""

batch_size = 256
num_prompts = len(final_user_prompts)

WORKERS = 10   # IMPORTANT: do NOT set workers=batch_size

for i in range(0, num_prompts, batch_size):
    begin = i
    end = min(begin + batch_size, num_prompts)
    current_prompts = final_user_prompts[begin:end]

    start = time.time()
    batch_results = run_parallel_map(system_prompt, current_prompts, workers=WORKERS)
    tags.iloc[begin:end, tags.columns.get_loc("out")] = batch_results

    duration = round(time.time() - start, 2)
    print(f"Processing batch: {begin//batch_size + 1}, Prompts: {begin} to {end-1}, Duration: {duration}s")

tags.to_csv("Mapping_landscape_ABM/Data/tagging/data_tags_v1.csv", index=False)
