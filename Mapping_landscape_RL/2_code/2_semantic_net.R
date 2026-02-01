require(tidyverse)
require(reticulate)
use_condaenv("form")
require(remotes)
Rcpp::sourceCpp("2_code/_helpers.cpp")

remotes::install_github("https://github.com/dwulff/memnet")

data = read_csv("1_data/data_cleaned_filtered.csv") |> mutate(text = paste0("Title: ", Title, ".\nAbstract: ", Abstract_cleaned))

# GENERATE TRAINING EXAMPLES -----
#reticulate::py_install("sentence-transformers")
#use_python("/path/to/python", required = TRUE)
sbert = import("sentence_transformers")
model = sbert$SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
embed = model$encode(data$text)

embed_cos = arma_cosine(embed)
embed_cos[embed_cos > 1] = 1 ; embed_cos[embed_cos < -1] = -1
embed_acos = 1-acos(embed_cos)/pi
rownames(embed_acos) = colnames(embed_acos) = data$id

clust = hclust(as.dist(1-embed_acos[as.character(data$id),as.character(data$id)])) |> cutree(k = 50)
names(clust) = data$id

pairs = crossing(i = data$id,
                 j = data$id) |> 
  filter(i < j) |> 
  mutate(cl_i = clust[as.character(i)],
         cl_j = clust[as.character(j)],
         cos = embed_acos[cbind(as.character(i), as.character(j))])

set.seed(100)
train_pairs = lapply(1:50, function(x){
  
  within = pairs |> filter(cl_i == x, cl_j == x) |> mutate(type = "within")
  between = pairs |> filter((cl_i == x & cl_j != x) | cl_i != x & cl_j == x) |> mutate(type = "between")
  
  sel_within = sample(nrow(within), min(1000, nrow(within)), prob = within$cos ** 10)
  sel_between = sample(nrow(between), min(1000, nrow(between)), prob = between$cos ** 10)
  
  within = within |> slice(sel_within)
  between = between |> slice(sel_between)
  
  tibble(within) |> bind_rows(between) |> mutate(cl = x)
  }) |> bind_rows() |> slice(sample(n(), 50000))

texts = data |> pull(text, id)
train_pairs = train_pairs |> 
  mutate(text_i = texts[as.character(i)],
         text_j = texts[as.character(j)])

write_csv(train_pairs, "1_data/semantic_training/train_pairs.csv")



# # PROCESS RATINGS ---------------------------------------------------------------------------------------------------------------------

train_pairs_ratings = read_csv("1_data/semantic_training/train_pairs_ratings.csv") |> 
  mutate(rating = out |> str_extract("Answer=[:digit:]+[:punct:]*$") |> str_remove("Answer=") |> str_remove_all("[:punct:]") |> as.numeric(),
         rating_scaled = rating / 100) |> 
  select(-1)

write_csv(train_pairs_ratings, "1_data/semantic_training/train_pairs_rating_clean.csv")


# # GENERATE NET -----

torch = import("torch")
sbert = import("sentence_transformers")
hub = import("huggingface_hub")
model = sbert$SentenceTransformer("dwulff/minilm-brl")

context = "An article on behavioral reinforcement learning:\n\n"
sem_emb = model$encode(paste0(context, data$text))
rownames(sem_emb) = data$id

saveRDS(sem_emb, "1_data/embs/semantic_emb.RDS")
