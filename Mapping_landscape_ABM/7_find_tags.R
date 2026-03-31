require(tidyverse)

run_dir <- "D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/embeddings/embs_1000/embs_1000_pca9_1sem_1aut_ref"

data <- readRDS(file.path(run_dir, "data_cleaned_filtered_tagged_clustered_fixed_with_journals.RDS"))

# -----------------------------
# FORCE continent mapping from geometry
# -----------------------------
data <- data |>
  mutate(
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

# optional: save corrected grouping back to the same file
saveRDS(data, file.path(run_dir, "data_cleaned_filtered_tagged_clustered_fixed_with_journals.RDS"))

# -----------------------------
# Helper: flatten tags safely
# -----------------------------
get_tag_counts <- function(df) {
  if (!"tags_clean" %in% names(df)) {
    return(tibble(tag = character(), n = integer()))
  }
  
  tags <- df$tags_clean |> unlist() |> as.character()
  tags <- tags[!is.na(tags) & tags != ""]
  
  tibble(tag = tags) |>
    count(tag, sort = TRUE)
}

# -----------------------------
# Generic ABM tags to ignore
# case-insensitive
# -----------------------------
drop_tags <- c(
  "agent-based modelling",
  "agent based modelling",
  "agent-based modeling",
  "agent based modeling",
  "agent simulations",
  "agent-based simulation",
  "multi-agent simulation",
  "agent-based model",
  "agent-based models"
)

# -----------------------------
# COUNTRY-LEVEL summaries
# -----------------------------
country_ids <- sort(unique(na.omit(data$country)))

country_label_summary <- lapply(country_ids, function(cl) {
  df <- data |> filter(country == cl)
  
  tag_counts <- get_tag_counts(df) |>
    filter(!tolower(tag) %in% tolower(drop_tags))
  
  journal_counts <- df |>
    filter(!is.na(`Source title`) & `Source title` != "") |>
    count(`Source title`, sort = TRUE)
  
  year_vals <- df$Year[!is.na(df$Year)]
  
  tibble(
    country = cl,
    continent = first(df$continent),
    n_articles = nrow(df),
    year_min = if (length(year_vals) > 0) min(year_vals) else NA_real_,
    year_median = if (length(year_vals) > 0) median(year_vals) else NA_real_,
    year_max = if (length(year_vals) > 0) max(year_vals) else NA_real_,
    top_tags = paste(head(tag_counts$tag, 10), collapse = " | "),
    top_journals = paste(head(journal_counts$`Source title`, 5), collapse = " | ")
  )
}) |>
  bind_rows()

print(country_label_summary, n = Inf)

readr::write_csv(
  country_label_summary,
  file.path(run_dir, "country_label_summary.csv")
)

# -----------------------------
# CONTINENT-LEVEL summaries
# -----------------------------
continent_ids <- sort(unique(na.omit(data$continent)))

continent_label_summary <- lapply(continent_ids, function(cont) {
  df <- data |> filter(continent == cont)
  
  tag_counts <- get_tag_counts(df) |>
    filter(!tolower(tag) %in% tolower(drop_tags))
  
  journal_counts <- df |>
    filter(!is.na(`Source title`) & `Source title` != "") |>
    count(`Source title`, sort = TRUE)
  
  member_countries <- df |>
    distinct(country) |>
    arrange(country) |>
    pull(country)
  
  year_vals <- df$Year[!is.na(df$Year)]
  
  tibble(
    continent = cont,
    countries = paste(member_countries, collapse = ", "),
    n_articles = nrow(df),
    year_min = if (length(year_vals) > 0) min(year_vals) else NA_real_,
    year_median = if (length(year_vals) > 0) median(year_vals) else NA_real_,
    year_max = if (length(year_vals) > 0) max(year_vals) else NA_real_,
    top_tags = paste(head(tag_counts$tag, 15), collapse = " | "),
    top_journals = paste(head(journal_counts$`Source title`, 8), collapse = " | ")
  )
}) |>
  bind_rows()

print(continent_label_summary, n = Inf)

readr::write_csv(
  continent_label_summary,
  file.path(run_dir, "continent_label_summary.csv")
)

cat("Finished.\n")
cat("Continent grouping was overwritten using your geometry-based mapping.\n")