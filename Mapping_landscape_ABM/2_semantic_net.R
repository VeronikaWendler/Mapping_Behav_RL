require(tidyverse)
require(reticulate)
Sys.setenv(RETICULATE_CONDA = "~/apps/miniforge3/bin/conda")
use_condaenv("mapping_abm", required=TRUE)
print(py_config())

require(remotes)
Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")

remotes::install_github("https://github.com/dwulff/memnet")

data = read_csv("Mapping_landscape_ABM/Data/data_cleaned_filtered_4_300.csv") |> mutate(text = paste0("Title: ", Title, ".\nAbstract: ", Abstract_cleaned))

# GENERATE TRAINING EXAMPLES -----
#reticulate::py_install("sentence-transformers")
#use_python("/path/to/python", required = TRUE)

sbert = import("sentence_transformers")
model = sbert$SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")
embed = model$encode(data$text)

# embed_cos = arma_cosine(embed)
# embed_cos[embed_cos > 1] = 1 ; embed_cos[embed_cos < -1] = -1
# embed_acos = 1-acos(embed_cos)/pi
# rownames(embed_acos) = colnames(embed_acos) = data$id

# clust = hclust(as.dist(1-embed_acos[as.character(data$id),as.character(data$id)])) |> cutree(k = 50)
# names(clust) = data$id

# pairs = crossing(i = data$id,
#                  j = data$id) |> 
#   filter(i < j) |> 
#   mutate(cl_i = clust[as.character(i)],
#          cl_j = clust[as.character(j)],
#          cos = embed_acos[cbind(as.character(i), as.character(j))])

# set.seed(100)
# train_pairs = lapply(1:50, function(x){
  
#   within = pairs |> filter(cl_i == x, cl_j == x) |> mutate(type = "within")
#   between = pairs |> filter((cl_i == x & cl_j != x) | cl_i != x & cl_j == x) |> mutate(type = "between")
  
#   sel_within = sample(nrow(within), min(1000, nrow(within)), prob = within$cos ** 10)
#   sel_between = sample(nrow(between), min(1000, nrow(between)), prob = between$cos ** 10)
  
#   within = within |> slice(sel_within)
#   between = between |> slice(sel_between)
  
#   tibble(within) |> bind_rows(between) |> mutate(cl = x)
#   }) |> bind_rows() |> slice(sample(n(), 50000))

# texts = data |> pull(text, id)
# train_pairs = train_pairs |> 
#   mutate(text_i = texts[as.character(i)],
#          text_j = texts[as.character(j)])

# out_file <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training/train_pairs.csv"
# dir.create(dirname(out_file), recursive = TRUE, showWarnings = FALSE)
# write_csv(train_pairs, out_file)



# PROCESS RATINGS -----------------------------------------------------------------------------------------------

# train_pairs_ratings = read_csv("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training/train_pairs_ratings.csv") |> 
#   mutate(
#     rating = out |> str_extract("Answer=[:digit:]+") |> str_remove("Answer=") |> as.numeric(),
#     rating_scaled = rating / 100
#   ) |> 
#   filter(!is.na(rating_scaled)) |>          # drop ERROR rows / blanks
#   select(-1)                                # keep if your CSV has an X1 index column; otherwise remove

# write_csv(train_pairs_ratings, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training/train_pairs_rating_clean.csv")

###------

in_file  <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training/train_pairs_ratings.csv"
out_file <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/semantic_training/train_pairs_rating_clean.csv"
train_pairs_ratings <- read_csv(in_file, show_col_types = FALSE)

index_like <- c("X1", "X", "...1", "Unnamed: 0", "unnamed: 0")

if (names(train_pairs_ratings)[1] %in% index_like) {
  train_pairs_ratings <- train_pairs_ratings |> select(-1)
}

train_pairs_ratings <- train_pairs_ratings |>
  mutate(
    rating = str_extract(out, "Answer=\\d+") |> str_remove("Answer=") |> as.numeric(),
    rating_scaled = rating / 100
  ) |>
  filter(!is.na(rating_scaled))

write_csv(train_pairs_ratings, out_file)


# # GENERATE NET -----

# torch = import("torch")
# sbert = import("sentence_transformers")
# hub = import("huggingface_hub")
# model = sbert$SentenceTransformer("dwulff/minilm-brl")

# context = "An article on behavioral reinforcement learning:\n\n"
# sem_emb = model$encode(paste0(context, data$text))
# rownames(sem_emb) = data$id

# saveRDS(sem_emb, "Mapping_landscape_ABM/Data/embs/semantic_emb.RDS")


