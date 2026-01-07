# Mapping the landscape of behavioral reinforcement learning

Analysis code used in the article "Mapping the landscape of behavioral reinforcement learning" (Thoma, Bolenz, Tiede, Yang, Palminteri, Hertwig, & Wulff).

---

## 1. System Requirements

- **Programming Languages:** Analyses were performed in R (version 4.4.2) and Python (version 3.11)
- **Dependencies/Packages:** R packages: tidyverse (2.0.0), ggforce (0.5.0), patchwork (1.3.0), remotes (2.5.0), xml2 (1.3.6), rvest (1.0.4), reticulate (1.42.0), glmnet (4.1-10), Matrix (1.7-1), fastcluster (1.3.0), dbscan (1.2.2), ggh4x (0.3.0), tidytext (0.4.2); Python: sentence-transformers (5.1.1), requests (2.32.3), pandas (2.2.3), sklearn (1.6.1), torch (2.6.0), numpy (2.2.3), scipy (1.15.2)
- **Hardware Requirements:** Running large language models, such as Llama-3.3-70B, on a normal desktop computer will typically not be feasible. Check appropriate hardware for Llama-3.3-70B model (we used 4 x L40s with 48GB each): https://apxml.com/tools/vram-calculator. 


---

## 2. Installation Guide

### Step 1: Obtain the software
Download from https://osf.io/kxz9s/files 

### Step 2: Install dependencies
The required dependencies for the R and Python scripts are documented in each analysis script; the install time will be less than a few minutes for most packages. See https://huggingface.co/meta-llama/Llama-3.3-70B-Instruct for instructions on how to use the large language model (required for similarity ratings to finetune the embedding model and generating taxonomic tags).

## 3. Instructions for Use
A reduced demonstration dataset is not necessarily useful as some computations require substantial data input to return appropriate outcomes. For test purposes, we recommend to randomly select articles from the data.csv file. Make sure to set link the correct location of the files when running the code.
The duration of computations can take multiple hours for the similarity spaces and code requiring LLMs (similarity ratings for finetuning the embedding model and generating taxonomic tags), for instance, up to 4 hours for the semantic, reference, and author spaces, up to 14 hours for the LLM-generated similarity ratings and up to 2 hours for the LLM-generated taxnomic tags. The output files from these analyses are saved in the data folder to allow the reproduction of other analyses with more feasible computation times. 

### Reproducing Manuscript Results
To reproduce the results described in the manuscript refer to the respective code scripts:  

1. Data preprocessing, cleaning, and filtering based on a classifier to filter out articles out of scope (0_read.R, 1_clean_abstracts.R, 1_filter.R)
2. Construction of the similarity spaces (2_author_net.R, 2_references_net.R, 2_semantic_net.R, 2.1_semantic_ratings.py, 2.2_sbert_training.py)
3. Generating and analysing taxonomic tags; LLM prompts are documented in the python file (3_taxonomy.R, 3.1_tags.py)
4. Clustering of articles (4_clustering.R)
5. Visualizing the data processing pipeline (5_illustration.R)
6. Visualizing the landscape and labeling continents (6_map.R)
7. Creating an overview plot of countries (7_overview.R)
8. Analyzing the cohesion of continents and connectedness of countries (8_cohesion.R)
9. Creating visualization of the distribution of tags across the landscape (9_overlap.R)

---

## 5. License

This project is released under a CC By-SA license.

---

## 6. Code Availability

- **Repository:** https://osf.io/kxz9s

