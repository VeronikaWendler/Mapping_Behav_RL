require(dbscan)
require(tidyverse)
require(reticulate)

Sys.setenv(RETICULATE_CONDA = "~/apps/miniforge3/bin/conda")
use_condaenv("mapping_abm", required = TRUE)
print(py_config())

require(remotes)

Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")

if (!requireNamespace("memnet", quietly = TRUE)) {
  remotes::install_github("dwulff/memnet")
}
library(memnet)

data <- readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/data_cleaned_filtered_tagged.RDS") %>%
  mutate(
    id = as.integer(id),
    title_id = paste0(id, "_", str_to_lower(Title))
  )

# COMBINE EMB ----------

author_emb <- readRDS("Mapping_landscape_ABM/Data/embs_1000/author_emb.RDS")
references_emb <- readRDS("Mapping_landscape_ABM/Data/embs_1000/references_emb.RDS")
semantic_emb <- readRDS("Mapping_landscape_ABM/Data/embs_1000/semantic_emb.RDS")

# Safety check --------
# Make sure ROWS are papers/items, COLS are embedding dimensions

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

# Follow the spirit of the original scaling, but on item vectors

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

# author_emb <- author_emb / author_scale
# references_emb <- references_emb / ref_scale

# emb = cbind(
#   author_emb * 0.25,
#   references_emb * 0.25,
#   semantic_emb * 2
# )

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
  author_emb * 0.20,
  references_emb * 0.20,
  semantic_emb * 2.50
)

# emb = author_emb |> cbind(references_emb) |> cbind(semantic_emb)

colnames(emb) <- c(
  paste0("auth_", seq_len(ncol(author_emb))),
  paste0("ref_", seq_len(ncol(references_emb))),
  paste0("sem_", seq_len(ncol(semantic_emb)))
)

dir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000_pca4_2sem_0_25aut_ref"
dir.create(dir, recursive = TRUE, showWarnings = FALSE)

rownames(emb) <- data$id
saveRDS(emb, file.path(dir, "combined_emb.RDS"))

author_net <- embedR::er_compare_vectors(author_emb, metric = "arccos")
references_net <- embedR::er_compare_vectors(references_emb, metric = "arccos")
semantic_net <- embedR::er_compare_vectors(semantic_emb, metric = "arccos")

author_lines <- apply(author_net, 1, paste, collapse = ",")
references_lines <- apply(references_net, 1, paste, collapse = ",")
semantic_lines <- apply(semantic_net, 1, paste, collapse = ",")

out_dir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000_pca4_2sem_0_2aut_ref/nets"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

readr::write_lines(author_lines, file.path(out_dir, "author_net.txt"))
readr::write_lines(references_lines, file.path(out_dir, "references_net.txt"))
readr::write_lines(semantic_lines, file.path(out_dir, "semantic_net.txt"))

# CLUSTER ----------

stopifnot(is.matrix(emb))
storage.mode(emb) <- "double"

if (!requireNamespace("uwot", quietly = TRUE)) {
  install.packages("uwot", repos = "https://cloud.r-project.org")
}

# for umap and not pacmap
library(uwot)

set.seed(42)

# lyt <- uwot::umap(
#   X = emb,
#   n_neighbors = 30,
#   min_dist = 0.05,
#   metric = "cosine",
#   n_components = 2,
#   verbose = TRUE
# )

# lyt <- uwot::umap(
#   X = emb,
#   n_neighbors = 15,
#   min_dist = 0.25,
#   metric = "cosine",
#   n_components = 2,
#   verbose = TRUE
# )

pca <- prcomp(emb, center = TRUE, scale. = FALSE)
emb_pca <- pca$x[, 1:50]

lyt <- uwot::umap(
  X = emb_pca,
  n_neighbors = 15,
  min_dist = 0.25,
  spread = 3,
  metric = "cosine",
  n_components = 2,
  verbose = TRUE
)

lyt <- as.matrix(lyt)
cat("R dim:", paste(dim(lyt), collapse = " x "), "\n")

stopifnot(ncol(lyt) == 2)

colnames(lyt) <- c("lyt_x", "lyt_y")
rownames(lyt) <- rownames(emb)

cluster <- hclust(dist(lyt), method = "ward.D2")
clustering <- cutree(cluster, 15)

png(
  file.path(out_dir, "umap_clusters_wardD2_15clust_15neighb_0_25mindist.png"),
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