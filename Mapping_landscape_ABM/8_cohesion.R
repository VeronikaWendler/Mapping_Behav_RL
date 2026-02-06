require(tidyverse)
require(patchwork)
require(remotes)
require(viridis)

Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")

if (!requireNamespace("memnet", quietly = TRUE)) {
  remotes::install_github("dwulff/memnet")
}
library(memnet)

# ---------------------------
# Paths (EDIT emb_path if needed)
# ---------------------------
data_path <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged_clustered_objective.RDS"
emb_path  <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/combined_emb.RDS" 
out_png <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/continent_relations_ABM.png"

# ---------------------------
# Load data + embeddings
# ---------------------------
data <- readRDS(data_path)
emb  <- readRDS(emb_path)

stopifnot(is.matrix(emb) || inherits(emb, "Matrix"))

# Standardize year column to numeric `year` (optional; used only if you need ordering later)
if ("Year" %in% names(data) && !"year" %in% names(data)) data <- data %>% rename(year = Year)
if ("year" %in% names(data)) {
  data <- data %>%
    mutate(year = readr::parse_number(as.character(year))) %>%
    mutate(year = ifelse(year >= 1900 & year <= 2100, year, NA_real_))
}

# Required columns
needed <- c("title_id", "continent", "country", "lyt_x", "lyt_y")
missing <- setdiff(needed, names(data))
if (length(missing) > 0) stop("Missing columns in data: ", paste(missing, collapse = ", "))

# Ensure rownames align with title_id
if (is.null(rownames(emb))) {
  stop("Your embedding matrix has no rownames. It MUST match data$title_id order.")
}

# If embeddings are in same order but names differ, you can force alignment:
# emb <- emb[data$title_id, , drop = FALSE]

if (!all(data$title_id %in% rownames(emb))) {
  stop("Not all data$title_id are present in rownames(emb). Alignment mismatch.")
}
emb <- emb[data$title_id, , drop = FALSE]

# ---------------------------
# Build similarity nets
# ---------------------------
# Robust splitting:
# - If emb has 3 equal blocks: treat as author/ref/semantic
# - Else: treat everything as "combined" and set others = combined
p <- ncol(emb)

if (p %% 3 == 0) {
  d <- p / 3
  emb_a <- emb[, 1:d, drop = FALSE]
  emb_r <- emb[, (d+1):(2*d), drop = FALSE]
  emb_s <- emb[, (2*d+1):(3*d), drop = FALSE]
} else {
  message("Embedding dim not divisible by 3. Using full embedding for all nets.")
  emb_a <- emb_r <- emb_s <- emb
}

combined_net  <- arma_cosine(emb);   combined_net[is.na(combined_net)]  <- 0
author_net    <- arma_cosine(emb_a); author_net[is.na(author_net)]      <- 0
reference_net <- arma_cosine(emb_r); reference_net[is.na(reference_net)] <- 0
semantic_net  <- arma_cosine(emb_s); semantic_net[is.na(semantic_net)]   <- 0

rownames(combined_net) <- colnames(combined_net) <- data$title_id
rownames(author_net)   <- colnames(author_net)   <- data$title_id
rownames(reference_net)<- colnames(reference_net)<- data$title_id
rownames(semantic_net) <- colnames(semantic_net) <- data$title_id

# ---------------------------
# ABM: 5 continents (use your map labels)
# ---------------------------
continents <- tibble(
  continent = 1:5,
  number = 1:5,
  colors = viridis::mako(5, end = .8)
) %>%
  mutate(
    colors_white  = memnet::cmix(colors, "white", .5),
    colors_white2 = memnet::cmix(colors, "white", .7),
    labels = c(
      "Social Equity & Policy",
      "Norm Emergence & Coordination",
      "Collective Behavior & Emergence",
      "Business Networks & Markets",
      "Transportation & EV Adoption"
    )
  )

# ---------------------------
# Similarity between country-clusters
# ---------------------------
n_country <- length(unique(data$country))
if (!all(sort(unique(data$country)) == 1:n_country)) {
  # If your country IDs aren’t 1..K, map them
  country_map <- tibble(country_orig = sort(unique(data$country))) %>%
    mutate(country = row_number())
  data <- data %>% left_join(country_map, by = c("country" = "country_orig")) %>%
    rename(country_old = country.x, country = country.y)
}

cutoff <- 0.5
cutoffs <- c(
  quantile(combined_net[upper.tri(combined_net)],  cutoff),
  quantile(author_net[upper.tri(author_net)],      cutoff),
  quantile(reference_net[upper.tri(reference_net)],cutoff),
  quantile(semantic_net[upper.tri(semantic_net)],  cutoff)
)

above_cutoff <- function(x, cutoff) mean(x > cutoff)

combined_sim  <- matrix(NA_real_, n_country, n_country)
author_sim    <- matrix(NA_real_, n_country, n_country)
reference_sim <- matrix(NA_real_, n_country, n_country)
semantic_sim  <- matrix(NA_real_, n_country, n_country)

for (i in 1:n_country) {
  for (j in 1:n_country) {

    sel_i <- which(data$country == i)
    sel_j <- which(data$country == j)

    if (i == j) {
      # within-cluster: use upper triangle (no self pairs)
      combined_sim[i,j]  <- above_cutoff(combined_net[sel_i, sel_j][upper.tri(combined_net[sel_i, sel_j])],  cutoffs[1])
      author_sim[i,j]    <- above_cutoff(author_net[sel_i, sel_j][upper.tri(author_net[sel_i, sel_j])],      cutoffs[2])
      reference_sim[i,j] <- above_cutoff(reference_net[sel_i, sel_j][upper.tri(reference_net[sel_i, sel_j])],cutoffs[3])
      semantic_sim[i,j]  <- above_cutoff(semantic_net[sel_i, sel_j][upper.tri(semantic_net[sel_i, sel_j])],  cutoffs[4])
    } else {
      combined_sim[i,j]  <- above_cutoff(combined_net[sel_i, sel_j],  cutoffs[1])
      author_sim[i,j]    <- above_cutoff(author_net[sel_i, sel_j],    cutoffs[2])
      reference_sim[i,j] <- above_cutoff(reference_net[sel_i, sel_j], cutoffs[3])
      semantic_sim[i,j]  <- above_cutoff(semantic_net[sel_i, sel_j],  cutoffs[4])
    }
  }
}

# ---------------------------
# Join continent labels for each country-cluster (country -> continent)
# ---------------------------
cluster_meta <- data %>%
  select(country, continent) %>%
  distinct() %>%
  arrange(country) %>%
  left_join(continents %>% select(continent, labels), by = "continent")

# Expand to long for plotting continent-continent means
sims_full <- expand.grid(country_i = 1:n_country, country_j = 1:n_country) %>%
  as_tibble() %>%
  mutate(
    combined_sim  = c(combined_sim),
    author_sim    = c(author_sim),
    reference_sim = c(reference_sim),
    semantic_sim  = c(semantic_sim)
  ) %>%
  left_join(cluster_meta %>% rename(country_i = country, continent_i = continent, labels_i = labels),
            by = "country_i") %>%
  left_join(cluster_meta %>% rename(country_j = country, continent_j = continent, labels_j = labels),
            by = "country_j")

no_zero <- function(sim) stringr::str_remove(as.character(round(sim, 2)), "^0")

make_tile <- function(df, sim_col, title, lims = c(0, 1)) {
  df %>%
    group_by(continent_i, continent_j) %>%
    summarise(sim = mean(.data[[sim_col]], na.rm = TRUE),
              labels_i = first(labels_i),
              labels_j = first(labels_j),
              .groups = "drop") %>%
    ggplot(aes(x = labels_i, y = labels_j, fill = sim, label = no_zero(sim))) +
    geom_tile() +
    geom_text(color = "white", size = 3.2) +
    scale_fill_viridis_c(option = "E", end = .85, limits = lims) +
    theme_minimal() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1, size = 10, lineheight = .9),
      axis.text.y = element_text(size = 10, lineheight = .9),
      axis.title = element_blank(),
      plot.title = element_text(hjust = 0.5, size = 14)
    ) +
    guides(fill = "none") +
    labs(title = title)
}

p0 <- make_tile(sims_full, "combined_sim",  "Combined",  lims = c(0, 1))
p1 <- make_tile(sims_full, "author_sim",    "Author",    lims = c(0, 1))
p2 <- make_tile(sims_full, "reference_sim", "Reference", lims = c(0, 1))
p3 <- make_tile(sims_full, "semantic_sim",  "Semantic",  lims = c(0, 1))

p_tiles <- (p0 + p1 + p2 + p3) + plot_layout(ncol = 4)

ggsave(out_png, p_tiles, dpi = 300, width = 16, height = 5.5, units = "in", bg = "white")
cat("Saved:", out_png, "\n")

