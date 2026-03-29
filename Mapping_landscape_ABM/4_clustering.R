require(dbscan)
require(tidyverse)
require(reticulate)
Sys.setenv(RETICULATE_CONDA = "~/apps/miniforge3/bin/conda")
use_condaenv("mapping_abm", required=TRUE)
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
    title_id = paste0(id, "_", str_to_lower(`Title`))
  )


# COMBINE EMB ----------

author_emb = readRDS("Mapping_landscape_ABM/Data/embs_1000/author_emb.RDS")
references_emb = readRDS("Mapping_landscape_ABM/Data/embs_1000/references_emb.RDS")
semantic_emb = readRDS("Mapping_landscape_ABM/Data/embs_1000/semantic_emb.RDS")

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

  stop(sprintf("[%s] Cannot align items with ids. dim=%d x %d, n_ids=%d",
               name, d[1], d[2], length(ids)))
}

author_emb     <- coerce_rows_are_items(author_emb, data$id, "author_emb")
references_emb <- coerce_rows_are_items(references_emb, data$id, "references_emb")
semantic_emb   <- coerce_rows_are_items(semantic_emb, data$id, "semantic_emb")

# Follow the spirit of the original scaling, but on item vectors
author_norms     <- apply(author_emb, 1, function(x) sqrt(sum(x^2)))
references_norms <- apply(references_emb, 1, function(x) sqrt(sum(x^2)))
semantic_norms   <- apply(semantic_emb, 1, function(x) sqrt(sum(x^2)))

cat(sprintf("Mean norms: author=%.4f ; references=%.4f ; semantic=%.4f\n",
            mean(author_norms), mean(references_norms), mean(semantic_norms)))

author_scale <- mean(author_norms) / mean(semantic_norms)
ref_scale    <- mean(references_norms) / mean(semantic_norms)

cat(sprintf("Scale factors: author_scale=%.6f ; ref_scale=%.6f\n",
            author_scale, ref_scale))

# author_emb     <- author_emb / author_scale
# references_emb <- references_emb / ref_scale

# emb = cbind(
#   author_emb * 0.25,
#   references_emb * 0.25,
#   semantic_emb * 2
# )
#



row_l2_normalize <- function(mat) {
  mat <- as.matrix(mat)
  rs <- sqrt(rowSums(mat^2))
  rs[rs == 0] <- 1
  mat / rs
}

author_emb     <- row_l2_normalize(author_emb)
references_emb <- row_l2_normalize(references_emb)
semantic_emb   <- row_l2_normalize(semantic_emb)

emb <- cbind(
  author_emb * 0.20,
  references_emb * 0.20,
  semantic_emb * 2.50
)





# emb = author_emb |> cbind(references_emb) |> cbind(semantic_emb)
colnames(emb) <- c(
  paste0("auth_", seq_len(ncol(author_emb))),
  paste0("ref_",  seq_len(ncol(references_emb))),
  paste0("sem_",  seq_len(ncol(semantic_emb)))
)


dir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000_pca3_2_5sem_0_2aut_ref"
dir.create(dir, recursive = TRUE, showWarnings = FALSE)
rownames(emb) <- data$id
saveRDS(emb, file.path(dir, "combined_emb.RDS"))

author_net = embedR::er_compare_vectors(author_emb, metric="arccos")
references_net = embedR::er_compare_vectors(references_emb, metric="arccos")
semantic_net = embedR::er_compare_vectors(semantic_emb, metric="arccos")

author_lines <- apply(author_net, 1, paste, collapse = ",")
references_lines <- apply(references_net, 1, paste, collapse = ",")
semantic_lines <- apply(semantic_net, 1, paste, collapse = ",")

out_dir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000_pca3_2_5sem_0_2aut_ref/nets"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
readr::write_lines(author_lines,     file.path(out_dir, "author_net.txt"))
readr::write_lines(references_lines, file.path(out_dir, "references_net.txt"))
readr::write_lines(semantic_lines,   file.path(out_dir, "semantic_net.txt"))

# CLUSTER ----------
stopifnot(is.matrix(emb))
storage.mode(emb) <- "double"

if (!requireNamespace("uwot", quietly = TRUE)) {
  install.packages("uwot", repos = "https://cloud.r-project.org")
}
# for umpa and not pacmap
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
#emb_pca <- pca$x[, 1:50]
# emb_pca <- pca$x[, 1:20]

emb_pca <- pca$x[, 1:20]


# lyt <- uwot::umap(
#   X = emb_pca,
#   n_neighbors = 15,
#   min_dist = 0.5,
#   spread = 5,
#   metric = "cosine",
#   n_components = 2,
#   verbose = TRUE
# )

lyt <- uwot::umap(
  X = emb_pca,
  n_neighbors = 15,
  min_dist = 0.5,
  spread = 5,
  repulsion_strength = 2,
  metric = "cosine",
  n_components = 2,
  verbose = TRUE
)


lyt <- as.matrix(lyt)
cat("R dim:", paste(dim(lyt), collapse = " x "), "\n")
stopifnot(ncol(lyt) == 2)

colnames(lyt) <- c("lyt_x", "lyt_y")
rownames(lyt) <- rownames(emb)

cluster = hclust(dist(lyt), method = "ward.D2")
clustering = cutree(cluster, 15)

png(file.path(out_dir, "umap_clusters_wardD2_15clust_15neighb_0_25mindist.png"), width = 1200, height = 900)
j <- matrix(rnorm(nrow(lyt) * 2, sd = .05), ncol = 2)
plot(lyt[,1] + j[,1], lyt[,2] + j[,2], pch = 16, cex = 1, col = clustering + 3)
invisible(sapply(1:max(clustering), function(k) {
  text(mean(lyt[clustering == k, 1]), mean(lyt[clustering == k, 2]), labels = k, col = "grey50")
}))
dev.off()


#
# pacmap <- import("pacmap")

# set.seed(42)

# for ward 2_2
# model <- pacmap$PaCMAP(
#   n_components = as.integer(2),
#   n_neighbors  = as.integer(20),
#   MN_ratio     = 0.5,
#   FP_ratio     = 2.0,
#   distance     = "angular"
# )

# # for ward 2 _3 
# model <- pacmap$PaCMAP(
#   n_components = as.integer(2),
#   n_neighbors  = as.integer(25),
#   MN_ratio     = 1.0,
#   FP_ratio     = 4.0,
#   distance     = "angular"
# )



# lyt_raw <- model$fit_transform(as.matrix(emb))

# if (reticulate::is_py_object(lyt_raw)) {
#   shape <- reticulate::py_to_r(lyt_raw$shape)
#   cat("numpy shape:", shape[1], "x", shape[2], "\n")
#   lyt <- reticulate::py_to_r(lyt_raw)
# } else {
#   cat("fit_transform returned R object of class:", class(lyt_raw), "\n")
#   if (is.numeric(lyt_raw) && length(lyt_raw) == nrow(emb) * 2) {
#     lyt <- matrix(lyt_raw, ncol = 2, byrow = TRUE)
#   } else {
#     lyt <- as.matrix(lyt_raw)
#   }
# }

# cat("R dim:", paste(dim(lyt), collapse=" x "), "\n")
# stopifnot(ncol(lyt) == 2)

# colnames(lyt) <- c("lyt_x", "lyt_y")
# rownames(lyt) <- rownames(emb)

# cluster = hclust(dist(lyt), method = "ward.D2")       # instead of complete do ward.D2
# clustering = cutree(cluster, 15)

# # j <- matrix(rnorm(nrow(lyt)*2, sd=.3), ncol=2)
# # plot(lyt[,1] + j[,1], lyt[,2] + j[,2], pch=16, cex=1, col=clustering + 3)
# # sapply(1:max(clustering), function(x) text(mean(lyt[clustering==x,1]), mean(lyt[clustering==x,2]), label = x, col="grey50"))

# png(file.path(out_dir, "pacmap_clusters_ward_D2_3_15clust.png"), width=1200, height=900)
# j <- matrix(rnorm(nrow(lyt)*2, sd=.05), ncol=2)
# plot(lyt[,1] + j[,1], lyt[,2] + j[,2], pch=16, cex=1, col=clustering + 3)
# invisible(sapply(1:max(clustering), function(k) {
#   text(mean(lyt[clustering==k,1]), mean(lyt[clustering==k,2]), labels = k, col="grey50")
# }))
# dev.off()


# clusters <- as_tibble(lyt, rownames = "id") |>
#   mutate(
#     id = as.integer(id),   
#     country = clustering,
#     continent=case_when(
#       country %in% c(1, 17, 18 ) ~ 1,
#       country %in% c(2, 5, 7, 10, 11, 12, 13, 28) ~ 2,
#       country %in% c(3, 4, 6, 8, 25, 27, 29) ~ 3,
#       country %in% c(9, 14, 19, 30 ) ~ 4,
#       country %in% c(15, 20, 22, 23, 24 ) ~ 5,
#       country %in% c(16, 21, 26) ~ 6,
#       TRUE ~ NA_real_
#       )
#   )

# 1              1, 17, 18                            588           3
# 2              2 2, 5, 7, 10, 11, 12, 13, 28         2385           8
# 3              3 3, 4, 6, 8, 25, 27, 29              1391           7
# 4              4 9, 14, 19, 30                        743           4
# 5              5 15, 20, 22, 23, 24                   910           5
# 6              6 16, 21, 26                           453           3


#data <- data |> left_join(clusters, by = "id")
#saveRDS(data, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/data_cleaned_filtered_tagged_clustered_MN_ratio2.RDS")




