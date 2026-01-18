import requests
import concurrent.futures
import pandas as pd
import time
from functools import partial # Import partial

# an API gets imported, ok
with open("1_data/semantic_training/api.txt", "r") as f:
  api = f.readlines()

url = api[0]

headers = {
    'Authorization': api[1],
    'Content-Type': 'application/json'
}

def run(system, user):
    data = {
        "model": "Llama-3.3-70B-Instruct",
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user}
        ]
    }

    response = requests.post(url, headers=headers, json=data)
    return response.json()["choices"][0]["message"]["content"]


def run_parallel_map(system_prompt, users, workers=10):
    func = partial(run, system_prompt) 
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        results = list(executor.map(func, users, chunksize=max(1, len(users)//workers))) # chunksize can help performance
    return results


train = pd.read_csv("Mapping_landscape_ABM/Data/semantic_training/train_pairs.csv")

pairs = ["-- Article 1 --\n" + i + "\n\n-- Article 2 --\n" + j for i, j in zip(train["text_i"].values, train["text_j"].values)]

system_prompt = "You are an expert in the academic literature on behavioral agent-based modeling, who accurately discerns differences in specific research topics."
task_description = """Your primary task is to compare the following two articles (Article 1 and Article 2) based *only* on their provided titles and abstracts. Both articles operate within the general field of behavioral agent-based modeling (ABM).\n\nYour goal is to determine how similar their *specific research topics* are within the ABM context. Do they investigate the same sub-problem, mechanism, or research question?"""
format_instructions = """
First, provide your reasoning:
**Reasoning:**
[Provide a brief explanation here comparing the specific research topics, methodologies, or questions apparent in the titles/abstracts. Highlight similarities and differences relevant to the BRL field.]

Second, immediately following your reasoning, provide the numerical rating on a new line using the specified format.
Rate the similarity of the specific research topics on a scale from 0 to 100:
* **0:** Completely different specific research topics within ABM.
* **50:** The articles share significant common ground but ultimately address distinct specific research topics within ABM.
* **100:** The articles address the same specific research topic within ABM.

Strictly format the rating line *exactly* like this, with no extra text before or after:
Answer=[rating]"""

prompt_prefix = task_description + "\n\n"

final_user_prompts = [
    prompt_prefix
    + f"Here are the articles to evaluate:\n\n{pair}\n\n" # The actual pair data
    + format_instructions
    for pair in pairs
]

train["out"] = ""

# --- Revised Loop ---
batch_size = 100
num_prompts = len(final_user_prompts)
for i in range(411 * batch_size, num_prompts, batch_size):
    begin = i
    end = min(begin + batch_size, num_prompts) 
    current_prompts = final_user_prompts[begin:end]
    start = time.time()
    batch_results = run_parallel_map(system_prompt, current_prompts, workers=100) 
    train.iloc[begin:end, train.columns.get_loc('out')] = batch_results 
    duration = round(time.time() - start, 2)
    print(f"Processing batch: {begin//batch_size + 1}, Prompts: {begin} to {end-1}, Duration: {duration}s")

train.to_csv("Mapping_landscape_ABM/Data/semantic_training/train_pairs_ratings.csv", index=False)



