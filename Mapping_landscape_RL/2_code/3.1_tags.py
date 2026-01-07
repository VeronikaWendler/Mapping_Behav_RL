import requests
import concurrent.futures
import pandas as pd
import time
import sys
import itertools
from functools import partial 

with open("1_data/semantic_training/api.txt", "r") as f:
  api = f.readlines()

url = api[0]

headers = {
    'Authorization': api[1],
    'Content-Type': 'application/json'
}

def run(system, user):
  
    data = {
        "model": "meta-llama/Llama-3.3-70B-Instruct",
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user}
        ], 
        "max_tokens": 500
    }
    response = requests.post(url, headers=headers, json=data)
    return response.json()["choices"][0]["message"]["content"]


def run_parallel_map(system_prompt, users, workers=10):
    func = partial(run, system_prompt) 
    with concurrent.futures.ThreadPoolExecutor(max_workers=workers) as executor:
        results = list(executor.map(func, users, chunksize=max(1, len(users)//workers))) # chunksize can help performance
    return results


data = pd.read_csv("1_data/data_cleaned_filtered.csv")
data["text"] = "Title: " + data["Title"].values + ".\nAbstract: " + data["Abstract_cleaned"].values


system_prompt = (
    "You are an expert research assistant specializing in behavioral reinforcement learning.\n"
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
    "1. **Reasoning (Brief):** First, provide a concise explanation of your tagging choices. Justify how your selected tags cover the article's subject and methodology, and briefly mention how you ensured non-redundancy and adherence to the article's language.\n"
    "2. **Taxonomic Tags:** Immediately following your reasoning, provide the taxonomic tags. They must be separated by a semicolon (;) and enclosed within 'Answer=[...]'.\n\n"
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

#run(system_prompt, final_user_prompts[7])

tags = pd.DataFrame({"id": data["id"].values})
tags["out"] = ""

batch_size = 256
num_prompts = len(final_user_prompts)
for i in range(0, num_prompts, batch_size):
    begin = i
    end = min(begin + batch_size, num_prompts) 
    current_prompts = final_user_prompts[begin:end]
    start = time.time()
    batch_results = run_parallel_map(system_prompt, current_prompts, workers=batch_size) 
    tags.iloc[begin:end, tags.columns.get_loc('out')] = batch_results 
    duration = round(time.time() - start, 2)
    print(f"Processing batch: {begin//batch_size + 1}, Prompts: {begin} to {end-1}, Duration: {duration}s")


tags.to_csv("1_data/tagging/data_tags_v1.csv")



