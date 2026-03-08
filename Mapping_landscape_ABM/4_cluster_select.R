library(tidyverse)

infile <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/data_cleaned_filtered_tagged_clustered.RDS"
outdir <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/cluster_inspection"

dir.create(outdir, recursive = TRUE, showWarnings = FALSE)

data <- readRDS(infile) %>%
  select(any_of(c("id", "Title", "country", "tags_clean", "lyt_x", "lyt_y", "Source title")))

# Cluster sizes
cluster_sizes <- data %>%
  count(country, sort = TRUE)

write_csv(cluster_sizes, file.path(outdir, "cluster_sizes.csv"))

#Top cleaned tags per cluster
cluster_top_tags <- data %>%
  tidyr::unnest_longer(tags_clean) %>%
  rename(tag = tags_clean) %>%
  filter(!is.na(tag), tag != "") %>%
  count(country, tag, sort = TRUE) %>%
  left_join(cluster_sizes, by = "country") %>%
  mutate(prop = n.x / n.y) %>%
  rename(tag_count = n.x, cluster_size = n.y) %>%
  group_by(country) %>%
  slice_head(n = 15) %>%
  ungroup()

write_csv(cluster_top_tags, file.path(outdir, "cluster_top_tags.csv"))

# titles per cluster
set.seed(42)

cluster_sample_titles <- data %>%
  group_by(country) %>%
  mutate(rand = runif(n())) %>%
  arrange(rand, .by_group = TRUE) %>%
  slice_head(n = 8) %>%
  ungroup() %>%
  select(-rand) %>%
  mutate(tags_clean = sapply(tags_clean, function(x) paste(x, collapse = "; "))) %>%
  select(country, id, Title, tags_clean, any_of(c("Source title")))

write_csv(cluster_sample_titles, file.path(outdir, "cluster_sample_titles.csv"))

# 4) Cluster centroids
cluster_centroids <- data %>%
  group_by(country) %>%
  summarise(
    n = n(),
    lyt_x = mean(lyt_x, na.rm = TRUE),
    lyt_y = mean(lyt_y, na.rm = TRUE),
    .groups = "drop"
  )

write_csv(cluster_centroids, file.path(outdir, "cluster_centroids.csv"))

# 5) Nearest neighboring clusters on the map
centroid_dist <- as.matrix(dist(cluster_centroids %>% select(lyt_x, lyt_y)))
rownames(centroid_dist) <- cluster_centroids$country
colnames(centroid_dist) <- cluster_centroids$country

nearest_neighbors <- purrr::map_dfr(seq_len(nrow(cluster_centroids)), function(i) {
  country_i <- cluster_centroids$country[i]
  d <- centroid_dist[i, ]
  d[i] <- Inf
  ord <- order(d)

  tibble(
    country = country_i,
    neighbor_rank = 1:5,
    neighbor_country = as.integer(names(d)[ord[1:5]]),
    distance = as.numeric(d[ord[1:5]])
  )
})

write_csv(nearest_neighbors, file.path(outdir, "cluster_nearest_neighbors.csv"))

# 6) Representative titles closest to centroid
cluster_representative_titles <- data %>%
  left_join(cluster_centroids, by = "country", suffix = c("", "_centroid")) %>%
  mutate(
    dist_to_centroid = sqrt((lyt_x - lyt_x_centroid)^2 + (lyt_y - lyt_y_centroid)^2),
    tags_clean = sapply(tags_clean, function(x) paste(x, collapse = "; "))
  ) %>%
  group_by(country) %>%
  arrange(dist_to_centroid, .by_group = TRUE) %>%
  slice_head(n = 8) %>%
  ungroup() %>%
  select(country, id, Title, dist_to_centroid, tags_clean, any_of(c("Source title")))

write_csv(
  cluster_representative_titles,
  file.path(outdir, "cluster_representative_titles.csv")
)

cat("Saved inspection files to:\n", outdir, "\n")