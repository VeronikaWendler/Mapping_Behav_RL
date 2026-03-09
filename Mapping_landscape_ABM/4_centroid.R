
require(tidyverse)

# -----------------------------
# Input / output
# -----------------------------
data_path <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/data_cleaned_filtered_tagged_clustered_MN_ratio3.RDS"
out_dir   <- "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/continent_diagnostics"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

data <- readRDS(data_path)

stopifnot(all(c("country", "lyt_x", "lyt_y") %in% names(data)))
stopifnot(!any(is.na(data$country)))
stopifnot(!any(is.na(data$lyt_x)))
stopifnot(!any(is.na(data$lyt_y)))

# -----------------------------
# 1) Country centroids
# -----------------------------
country_centroids <- data |>
  group_by(country) |>
  summarise(
    cx = mean(lyt_x),
    cy = mean(lyt_y),
    n_papers = n(),
    .groups = "drop"
  ) |>
  arrange(country)

readr::write_csv(country_centroids, file.path(out_dir, "country_centroids.csv"))

# -----------------------------
# 2) Distance matrix + nearest neighbors
# -----------------------------
coords <- as.matrix(country_centroids[, c("cx", "cy")])
rownames(coords) <- country_centroids$country

dist_mat <- as.matrix(dist(coords))
diag(dist_mat) <- Inf

nearest_df <- purrr::map_dfr(seq_len(nrow(dist_mat)), function(i) {
  ord <- order(dist_mat[i, ])
  tibble(
    country = country_centroids$country[i],
    neighbor_1 = country_centroids$country[ord[1]],
    dist_1     = dist_mat[i, ord[1]],
    neighbor_2 = country_centroids$country[ord[2]],
    dist_2     = dist_mat[i, ord[2]],
    neighbor_3 = country_centroids$country[ord[3]],
    dist_3     = dist_mat[i, ord[3]]
  )
})

readr::write_csv(nearest_df, file.path(out_dir, "country_nearest_neighbors_from_layout.csv"))

# Optional full pairwise distances
# 3) Automatic continent grouping from country centroids
# -----------------------------
hc <- hclust(dist(coords), method = "complete")

country_centroids <- country_centroids |>
  mutate(continent_auto = cutree(hc, k = 6))

readr::write_csv(country_centroids, file.path(out_dir, "country_to_auto_continent_k6.csv"))

# -----------------------------
# 4) Join back to papers
# -----------------------------
data_auto <- data |>
  left_join(
    country_centroids |> select(country, continent_auto),
    by = "country"
  )

saveRDS(data_auto, file.path(out_dir, "data_with_auto_continent_k6.RDS"))

# -----------------------------
# 5) Summary table for inspection
# -----------------------------
continent_summary <- country_centroids |>
  group_by(continent_auto) |>
  summarise(
    countries = paste(sort(country), collapse = ", "),
    total_papers = sum(n_papers),
    n_countries = n(),
    .groups = "drop"
  ) |>
  arrange(continent_auto)

readr::write_csv(continent_summary, file.path(out_dir, "auto_continent_summary_k6.csv"))

# -----------------------------
# 6) Plot A: all papers + country centroid labels
# -----------------------------
p1 <- ggplot(data, aes(x = lyt_x, y = lyt_y)) +
  geom_point(size = 0.6, alpha = 0.7) +
  geom_text(
    data = country_centroids,
    aes(x = cx, y = cy, label = country),
    inherit.aes = FALSE,
    size = 3.5,
    fontface = "bold"
  ) +
  theme_void() +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA)
  )

ggsave(
  filename = file.path(out_dir, "country_centroids_labeled.png"),
  plot = p1,
  width = 8, height = 8, dpi = 300, bg = "white"
)

# -----------------------------
# 7) Plot B: papers colored by auto-continent
# -----------------------------
p2 <- ggplot(data_auto, aes(x = lyt_x, y = lyt_y, color = factor(continent_auto))) +
  geom_point(size = 0.7, alpha = 0.8) +
  geom_text(
    data = country_centroids,
    aes(x = cx, y = cy, label = country, color = factor(continent_auto)),
    inherit.aes = FALSE,
    size = 3,
    fontface = "bold"
  ) +
  theme_void() +
  theme(
    plot.background = element_rect(fill = "white", colour = NA),
    panel.background = element_rect(fill = "white", colour = NA)
  ) +
  guides(color = guide_legend(title = "Auto continent"))

ggsave(
  filename = file.path(out_dir, "auto_continent_map_k6.png"),
  plot = p2,
  width = 8, height = 8, dpi = 300, bg = "white"
)

# -----------------------------
# 8) Plot C: dendrogram of countries
# -----------------------------
png(file.path(out_dir, "country_centroid_dendrogram_k6.png"),
    width = 1800, height = 1200, res = 200, bg = "white")
plot(hc, main = "Hierarchical clustering of country centroids", xlab = "", sub = "")
rect.hclust(hc, k = 6, border = 2:7)
dev.off()

cat("Saved outputs to:\n", out_dir, "\n")
print(continent_summary)