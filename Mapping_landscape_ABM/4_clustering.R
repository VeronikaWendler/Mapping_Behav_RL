install.packages(c("remotes", "Rcpp", "RcppArmadillo"), repos = "https://cloud.r-project.org")

require(dbscan)
require(tidyverse)
require(remotes)
require(Rcpp)
require(RcppArmadillo)
require(reticulate)

# Use the exact Python inside your conda env
use_python(
  "C:/Users/vaw508/AppData/Local/anaconda3/envs/mapping_abm/python.exe",
  required = TRUE
)
print(py_config())

pacmap <- import("pacmap")

Rcpp::sourceCpp("D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/_helpers.cpp")

if (!requireNamespace("memnet", quietly = TRUE)) {
  remotes::install_github("dwulff/memnet")
}
library(memnet)

er_compare_vectors <- function(embedding, metric = "cosine") {
  if (!is.matrix(embedding)) stop("Argument embedding must be a matrix.")
  if (!is.numeric(embedding)) stop("Argument embedding must be numeric.")
  if (!metric %in% c("cosine", "arccos", "pearson", "spearman", "euclidean")) {
    stop('metric must be one of "cosine", "arccos", "pearson", "spearman", "euclidean".')
  }
  
  if (metric == "cosine") {
    out <- arma_cosine(embedding)
    rownames(out) <- rownames(embedding)
    colnames(out) <- rownames(embedding)
    return(out)
  }
  
  if (metric == "arccos") {
    cosine <- arma_cosine(embedding)
    cosine[cosine > 1] <- 1
    cosine[cosine < -1] <- -1
    out <- 1 - acos(cosine) / pi
    rownames(out) <- rownames(embedding)
    colnames(out) <- rownames(embedding)
    return(out)
  }
  
  if (metric == "pearson") {
    return(stats::cor(t(embedding)))
  }
  
  if (metric == "spearman") {
    return(stats::cor(t(embedding), method = "spearman"))
  }
  
  if (metric == "euclidean") {
    return(as.matrix(stats::dist(embedding)))
  }
}

data <- readRDS("D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/embeddings/embs_1000/data_cleaned_filtered_tagged.RDS") %>%
  mutate(
    id = as.integer(id),
    title_id = paste0(id, "_", str_to_lower(Title))
  )

author_emb <- readRDS("D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/embeddings/embs_1000/author_emb.RDS")
references_emb <- readRDS("D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/embeddings/embs_1000/references_emb.RDS")
semantic_emb <- readRDS("D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/embeddings/embs_1000/semantic_emb.RDS")

coerce_rows_are_items <- function(mat, ids, name = "emb") {
  mat <- as.matrix(mat)
  d <- dim(mat)
  
  cat(sprintf("[%s] dim = %d x %d ; n_ids = %d\n", name, d[1], d[2], length(ids)))
  
  if (nrow(mat) == length(ids)) {
    cat(sprintf("[%s] keeping as-is: rows are items.\n", name))
    return(mat)
  }
  
  if (ncol(mat) == length(ids)) {
    cat(sprintf("[%s] transposing so rows become items.\n", name))
    return(t(mat))
  }
  
  stop(sprintf(
    "[%s] Cannot align items with ids. dim=%d x %d, n_ids=%d",
    name, d[1], d[2], length(ids)
  ))
}

author_emb <- coerce_rows_are_items(author_emb, data$id, "author_emb")
references_emb <- coerce_rows_are_items(references_emb, data$id, "references_emb")
semantic_emb <- coerce_rows_are_items(semantic_emb, data$id, "semantic_emb")

author_norms <- apply(author_emb, 1, function(x) sqrt(sum(x^2)))
references_norms <- apply(references_emb, 1, function(x) sqrt(sum(x^2)))
semantic_norms <- apply(semantic_emb, 1, function(x) sqrt(sum(x^2)))

cat(sprintf(
  "Mean norms: author=%.4f ; references=%.4f ; semantic=%.4f\n",
  mean(author_norms), mean(references_norms), mean(semantic_norms)
))

author_scale <- mean(author_norms) / mean(semantic_norms)
ref_scale <- mean(references_norms) / mean(semantic_norms)

cat(sprintf(
  "Scale factors: author_scale=%.6f ; ref_scale=%.6f\n",
  author_scale, ref_scale
))

row_l2_normalize <- function(mat) {
  mat <- as.matrix(mat)
  rs <- sqrt(rowSums(mat^2))
  rs[rs == 0] <- 1
  mat / rs
}

author_emb <- row_l2_normalize(author_emb)
references_emb <- row_l2_normalize(references_emb)
semantic_emb <- row_l2_normalize(semantic_emb)

emb <- cbind(
  author_emb * 1,
  references_emb * 1,
  semantic_emb * 1
)

colnames(emb) <- c(
  paste0("auth_", seq_len(ncol(author_emb))),
  paste0("ref_", seq_len(ncol(references_emb))),
  paste0("sem_", seq_len(ncol(semantic_emb)))
)

dir <- "D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/embeddings/embs_1000/embs_1000_pca9_1sem_1aut_ref"
dir.create(dir, recursive = TRUE, showWarnings = FALSE)

rownames(emb) <- data$id
saveRDS(emb, file.path(dir, "combined_emb.RDS"))

author_net <- er_compare_vectors(author_emb, metric = "arccos")
references_net <- er_compare_vectors(references_emb, metric = "arccos")
semantic_net <- er_compare_vectors(semantic_emb, metric = "arccos")

author_lines <- apply(author_net, 1, paste, collapse = ",")
references_lines <- apply(references_net, 1, paste, collapse = ",")
semantic_lines <- apply(semantic_net, 1, paste, collapse = ",")

out_dir <- file.path(dir, "nets")
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

readr::write_lines(author_lines, file.path(out_dir, "author_net.txt"))
readr::write_lines(references_lines, file.path(out_dir, "references_net.txt"))
readr::write_lines(semantic_lines, file.path(out_dir, "semantic_net.txt"))

stopifnot(is.matrix(emb))
storage.mode(emb) <- "double"

set.seed(42)

pca <- prcomp(emb, center = TRUE, scale. = FALSE)
var_explained <- (pca$sdev^2) / sum(pca$sdev^2)
cumvar <- cumsum(var_explained)
target_var <- 0.95
n_pcs <- which(cumvar >= target_var)[1]

cat(sprintf(
  "Using %d PCs to explain %.2f%% of total variance\n",
  n_pcs, 100 * cumvar[n_pcs]
))

pca_info <- tibble(
  pc = seq_along(var_explained),
  var_explained = var_explained,
  cumvar = cumvar
)

readr::write_csv(pca_info, file.path(dir, "pca_variance_summary.csv"))

emb_pca <- pca$x[, 1:n_pcs, drop = FALSE]

# -----------------------------
# CLUSTERING / PACMAP
# -----------------------------
model <- pacmap$PaCMAP(
  n_components = as.integer(2),
  n_neighbors  = as.integer(50),
  MN_ratio     = 3,
  FP_ratio     = 10.0,
  distance     = "angular"
)

lyt <- model$fit_transform(emb_pca)

lyt <- as.matrix(lyt)
cat("R dim:", paste(dim(lyt), collapse = " x "), "\n")

stopifnot(ncol(lyt) == 2)

colnames(lyt) <- c("lyt_x", "lyt_y")
rownames(lyt) <- rownames(emb)

cluster <- hclust(dist(lyt), method = "ward.D2")
clustering <- cutree(cluster, 20)

png(
  file.path(out_dir, "pacmap_clusters_wardD2_20clust_50neighb_MN3_FP10.png"),
  width = 1200,
  height = 900
)

j <- matrix(rnorm(nrow(lyt) * 2, sd = 0.05), ncol = 2)

plot(
  lyt[, 1] + j[, 1],
  lyt[, 2] + j[, 2],
  pch = 16,
  cex = 1,
  col = clustering + 3
)

invisible(sapply(1:max(clustering), function(k) {
  text(
    mean(lyt[clustering == k, 1]),
    mean(lyt[clustering == k, 2]),
    labels = k,
    col = "grey50"
  )
}))

dev.off()

clusters <- as.data.frame(lyt)
clusters$id <- rownames(lyt)

clusters <- as_tibble(clusters) |>
  mutate(
    id = as.integer(id),
    country = clustering,
    continent = case_when(
      country %in% c(6, 12) ~ 1,
      country %in% c(2, 15, 14) ~ 2,
      country %in% c(19) ~ 3,
      country %in% c(3, 7, 17, 13, 9, 16, 4) ~ 4,
      country %in% c(20) ~ 5,
      country %in% c(18, 10) ~ 6,
      country %in% c(8) ~ 7,
      country %in% c(5, 11) ~ 8,
      country %in% c(1) ~ 9,
      
      TRUE ~ NA_real_
    )
  )


data <- data |> left_join(clusters, by = "id")
saveRDS(data, file.path(dir, "data_cleaned_filtered_tagged_clustered.RDS"))
