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

data <- readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged.RDS") %>%
  mutate(
    id = as.integer(id),
    title_id = paste0(id, "_", str_to_lower(`Title`))
  )


# COMBINE EMB ----------

author_emb = readRDS("Mapping_landscape_ABM/Data/embs_300/author_emb.RDS")
references_emb = readRDS("Mapping_landscape_ABM/Data/embs_300/references_emb.RDS")
semantic_emb = readRDS("Mapping_landscape_ABM/Data/embs_300/semantic_emb.RDS")

# Safety check --------
get_item_norms <- function(mat, ids, name = "emb") {
  stopifnot(is.matrix(mat) || is.data.frame(mat))
  mat <- as.matrix(mat)
  d <- dim(mat)
  n_ids <- length(ids)

  cat(sprintf("[%s] dim = %d x %d ; n_ids = %d\n", name, d[1], d[2], n_ids))

  # Heuristic: items dimension should match n_ids (or be close)
  row_match <- (d[1] == n_ids)
  col_match <- (d[2] == n_ids)

  # If we have rownames/colnames, use them as stronger evidence
  rn_match <- !is.null(rownames(mat)) && sum(rownames(mat) %in% ids) > 0.9 * min(length(rownames(mat)), n_ids)
  cn_match <- !is.null(colnames(mat)) && sum(colnames(mat) %in% ids) > 0.9 * min(length(colnames(mat)), n_ids)

  if (row_match || rn_match) {
    cat(sprintf("[%s] Treating ROWS as items -> using row norms.\n", name))
    norms <- sqrt(rowSums(mat^2))
    orientation <- "rows_are_items"
  } else if (col_match || cn_match) {
    cat(sprintf("[%s] Treating COLS as items -> using col norms.\n", name))
    norms <- sqrt(colSums(mat^2))
    orientation <- "cols_are_items"
  } else {
    # Fall back: if one dimension is 384 (embedding dim) then items are the other
    if (d[2] == 384) {
      cat(sprintf("[%s] Heuristic: ncol==384 -> ROWS are items.\n", name))
      norms <- sqrt(rowSums(mat^2))
      orientation <- "rows_are_items_heuristic"
    } else if (d[1] == 384) {
      cat(sprintf("[%s] Heuristic: nrow==384 -> COLS are items.\n", name))
      norms <- sqrt(colSums(mat^2))
      orientation <- "cols_are_items_heuristic"
    } else {
      stop(sprintf("[%s] Can't infer item orientation. dim=%dx%d, n_ids=%d", name, d[1], d[2], n_ids))
    }
  }

  list(norms = norms, orientation = orientation)
}

# Run checks
author_info     <- get_item_norms(author_emb, data$id, "author_emb")
references_info <- get_item_norms(references_emb, data$id, "references_emb")
semantic_info   <- get_item_norms(semantic_emb, data$id, "semantic_emb")

# norms for scaling
author_norms     <- author_info$norms
references_norms <- references_info$norms
semantic_norms   <- semantic_info$norms

cat(sprintf("Mean norms: author=%.4f ; references=%.4f ; semantic=%.4f\n",
            mean(author_norms), mean(references_norms), mean(semantic_norms)))

# Sanity: after scaling, author/ref mean norm should match semantic mean norm
author_scale <- mean(author_norms) / mean(semantic_norms)
ref_scale    <- mean(references_norms) / mean(semantic_norms)

cat(sprintf("Scale factors: author_scale=%.6f ; ref_scale=%.6f\n", author_scale, ref_scale))


# end of safety check --------

author_emb     <- author_emb / author_scale
references_emb <- references_emb / ref_scale


emb = author_emb |> cbind(references_emb) |> cbind(semantic_emb)
#colnames(emb) = c(paste0("auth_", 1:384), paste0("ref_", 1:384), paste0("sem_", 1:384))
colnames(emb) <- c(paste0("auth_", seq_len(ncol(author_emb))),paste0("ref_",  seq_len(ncol(references_emb))),paste0("sem_",  seq_len(ncol(semantic_emb))))

rownames(emb) = data$id
saveRDS(emb, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/combined_emb.RDS")

author_net = embedR::er_compare_vectors(author_emb, metric="arccos")
references_net = embedR::er_compare_vectors(references_emb, metric="arccos")
semantic_net = embedR::er_compare_vectors(semantic_emb, metric="arccos")

author_lines <- apply(author_net, 1, paste, collapse = ",")
references_lines <- apply(references_net, 1, paste, collapse = ",")
semantic_lines <- apply(semantic_net, 1, paste, collapse = ",")

out_dir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/nets"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)
readr::write_lines(author_lines,     file.path(out_dir, "author_net.txt"))
readr::write_lines(references_lines, file.path(out_dir, "references_net.txt"))
readr::write_lines(semantic_lines,   file.path(out_dir, "semantic_net.txt"))

# CLUSTER ----------
stopifnot(is.matrix(emb))
storage.mode(emb) <- "double"

pacmap <- import("pacmap")
set.seed(42)
model <- pacmap$PaCMAP(
  n_components = as.integer(2),
  n_neighbors  = as.integer(50),
  MN_ratio     = 3,
  FP_ratio     = 10.0,
  distance     = "angular"
)

lyt_raw <- model$fit_transform(as.matrix(emb))

if (reticulate::is_py_object(lyt_raw)) {
  shape <- reticulate::py_to_r(lyt_raw$shape)
  cat("numpy shape:", shape[1], "x", shape[2], "\n")
  lyt <- reticulate::py_to_r(lyt_raw)
} else {
  cat("fit_transform returned R object of class:", class(lyt_raw), "\n")
  if (is.numeric(lyt_raw) && length(lyt_raw) == nrow(emb) * 2) {
    lyt <- matrix(lyt_raw, ncol = 2, byrow = TRUE)
  } else {
    lyt <- as.matrix(lyt_raw)
  }
}

cat("R dim:", paste(dim(lyt), collapse=" x "), "\n")
stopifnot(ncol(lyt) == 2)

colnames(lyt) <- c("lyt_x", "lyt_y")
rownames(lyt) <- rownames(emb)


cluster = hclust(dist(lyt), method = "complete")
clustering = cutree(cluster, 30)

# j <- matrix(rnorm(nrow(lyt)*2, sd=.3), ncol=2)
# plot(lyt[,1] + j[,1], lyt[,2] + j[,2], pch=16, cex=1, col=clustering + 3)
# sapply(1:max(clustering), function(x) text(mean(lyt[clustering==x,1]), mean(lyt[clustering==x,2]), label = x, col="grey50"))

png(file.path(out_dir, "pacmap_clusters.png"), width=1200, height=900)
j <- matrix(rnorm(nrow(lyt)*2, sd=.3), ncol=2)
plot(lyt[,1] + j[,1], lyt[,2] + j[,2], pch=16, cex=1, col=clustering + 3)
invisible(sapply(1:max(clustering), function(k) {
  text(mean(lyt[clustering==k,1]), mean(lyt[clustering==k,2]), labels = k, col="grey50")
}))
dev.off()


clusters <- as_tibble(lyt, rownames = "id") |>
  mutate(
    id = as.integer(id),   
    country = clustering,
    continent = case_when(
      country %in% c(11, 12, 30, 20, 14, 16, 4) ~ 1,
      country %in% c(9, 21, 15) ~ 2,
      country %in% c(27) ~ 3,
      country %in% c(28, 24, 8) ~ 4,
      country %in% c(26, 25, 5, 10, 2) ~ 5,
      country %in% c(19) ~ 6,
      country %in% c(13) ~ 7,
      country %in% c(1, 18, 7, 23, 3, 6, 22) ~ 8,
      country %in% c(17) ~ 9,
      country %in% c(29) ~ 10,
      TRUE ~ NA_real_
    )
  )

data <- data |> left_join(clusters, by = "id")
saveRDS(data, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged_clustered.RDS")
