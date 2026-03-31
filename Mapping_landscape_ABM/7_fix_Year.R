require(tidyverse)
require(readr)

run_dir <- "D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/embeddings/embs_1000/embs_1000_pca9_1sem_1aut_ref"

journal_rds <- file.path(run_dir, "data_cleaned_filtered_tagged_clustered_fixed_with_journals.RDS")
journal_csv <- file.path(run_dir, "data_cleaned_filtered_tagged_clustered_fixed_with_journals.csv")

ye_csv <- "D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/data_cleaned_filtered_4_300_YE.csv"

# read current repaired file
data_fixed <- readRDS(journal_rds) |>
  mutate(id = as.integer(id))

# read year source file
ye_data <- read_csv(ye_csv, show_col_types = FALSE) |>
  transmute(
    id = as.integer(id),
    Year_from_csv = suppressWarnings(parse_number(as.character(Year)))
  )

# attach Year by id
data_fixed <- data_fixed |>
  left_join(ye_data, by = "id") |>
  mutate(
    Year = coalesce(Year, Year_from_csv)
  ) |>
  select(-Year_from_csv)

# overwrite the same repaired files
saveRDS(data_fixed, journal_rds)
write_csv(data_fixed, journal_csv)

cat("Finished.\n")
cat("Updated RDS:\n", journal_rds, "\n")
cat("Updated CSV:\n", journal_csv, "\n")
cat("Non-missing Year count:", sum(!is.na(data_fixed$Year)), "\n")
cat("Non-missing Source title count:", sum(!is.na(data_fixed[["Source title"]])), "\n")










# require(tidyverse)
# require(jsonlite)
# require(readr)

# # ---------------------------------
# # PATHS
# # ---------------------------------
# run_dir <- "D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/embeddings/embs_1000/embs_1000_pca9_1sem_1aut_ref"

# rds_path <- file.path(run_dir, "data_cleaned_filtered_tagged_clustered.RDS")
# csv_path <- "D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/data_cleaned_filtered_4_300_YE.csv"


# out_rds <- file.path(run_dir, "data_cleaned_filtered_tagged_clustered_fixed_with_journals.RDS")
# out_csv <- file.path(run_dir, "data_cleaned_filtered_tagged_clustered_fixed_with_journals.csv")
# doi_lookup_csv <- file.path(run_dir, "doi_journal_lookup.csv")

# # ---------------------------------
# # READ INPUTS
# # ---------------------------------
# data_rds <- readRDS(rds_path)
# data_csv <- read_csv(csv_path, show_col_types = FALSE)

# # ---------------------------------
# # STANDARDIZE IDs
# # ---------------------------------
# data_rds$id <- as.integer(data_rds$id)
# data_csv$id <- as.integer(data_csv$id)

# # ---------------------------------
# # KEEP USEFUL CSV COLUMNS
# # ---------------------------------
# csv_meta <- tibble(
#   id = data_csv$id,
#   Year_csv = if ("Year" %in% names(data_csv)) suppressWarnings(parse_number(as.character(data_csv$Year))) else NA_real_,
#   DOI_csv = if ("DOI" %in% names(data_csv)) na_if(trimws(as.character(data_csv$DOI)), "") else NA_character_,
#   EID_csv = if ("EID" %in% names(data_csv)) na_if(trimws(as.character(data_csv$EID)), "") else NA_character_,
#   Link_csv = if ("Link" %in% names(data_csv)) na_if(trimws(as.character(data_csv$Link)), "") else NA_character_,
#   Publisher_csv = if ("Publisher" %in% names(data_csv)) na_if(trimws(as.character(data_csv$Publisher)), "") else NA_character_,
#   Source_csv = if ("Source" %in% names(data_csv)) na_if(trimws(as.character(data_csv$Source)), "") else NA_character_,
#   Title_csv = if ("Title" %in% names(data_csv)) na_if(trimws(as.character(data_csv$Title)), "") else NA_character_
# )

# # ---------------------------------
# # MERGE
# # ---------------------------------
# data_fixed <- left_join(data_rds, csv_meta, by = "id")

# # ---------------------------------
# # HELPER
# # ---------------------------------
# coalesce_if_exists <- function(df, base_col, new_col) {
#   if (base_col %in% names(df) && new_col %in% names(df)) {
#     df[[base_col]] <- dplyr::coalesce(df[[base_col]], df[[new_col]])
#   } else if (!(base_col %in% names(df)) && new_col %in% names(df)) {
#     df[[base_col]] <- df[[new_col]]
#   }
#   df
# }

# # ---------------------------------
# # FILL MISSING FIELDS FROM CSV
# # ---------------------------------
# data_fixed <- coalesce_if_exists(data_fixed, "Year", "Year_csv")
# data_fixed <- coalesce_if_exists(data_fixed, "DOI", "DOI_csv")
# data_fixed <- coalesce_if_exists(data_fixed, "EID", "EID_csv")
# data_fixed <- coalesce_if_exists(data_fixed, "Link", "Link_csv")
# data_fixed <- coalesce_if_exists(data_fixed, "Publisher", "Publisher_csv")
# data_fixed <- coalesce_if_exists(data_fixed, "Source", "Source_csv")
# data_fixed <- coalesce_if_exists(data_fixed, "Title", "Title_csv")

# # if Source title doesn't exist yet, create it
# if (!("Source title" %in% names(data_fixed))) {
#   data_fixed[["Source title"]] <- NA_character_
# }

# # clean DOI and Source title
# if ("DOI" %in% names(data_fixed)) {
#   data_fixed$DOI <- na_if(trimws(as.character(data_fixed$DOI)), "")
# }
# if ("Source title" %in% names(data_fixed)) {
#   data_fixed[["Source title"]] <- na_if(trimws(as.character(data_fixed[["Source title"]])), "")
# }

# # ---------------------------------
# # DOI LOOKUP FUNCTION
# # ---------------------------------
# get_journal_from_doi <- function(doi) {
#   if (is.na(doi) || trimws(doi) == "") return(NA_character_)
  
#   url <- paste0("https://api.crossref.org/works/", URLencode(trimws(doi), reserved = TRUE))
  
#   out <- tryCatch({
#     txt <- readLines(url, warn = FALSE, encoding = "UTF-8")
#     js <- jsonlite::fromJSON(paste(txt, collapse = "\n"))
    
#     title <- js$message$`container-title`
#     if (is.null(title) || length(title) == 0) {
#       NA_character_
#     } else {
#       as.character(title[[1]])
#     }
#   }, error = function(e) {
#     NA_character_
#   })
  
#   Sys.sleep(0.1)
#   out
# }

# # ---------------------------------
# # FIND DOIs NEEDING LOOKUP
# # ---------------------------------
# need_lookup <- is.na(data_fixed[["Source title"]]) &
#   !is.na(data_fixed$DOI) &
#   trimws(data_fixed$DOI) != ""

# unique_dois <- unique(data_fixed$DOI[need_lookup])

# cat("Rows in RDS:", nrow(data_rds), "\n")
# cat("Rows in CSV:", nrow(data_csv), "\n")
# cat("Rows after merge:", nrow(data_fixed), "\n")
# cat("Missing Year after merge:", sum(is.na(data_fixed$Year)), "\n")
# cat("DOIs needing journal lookup:", length(unique_dois), "\n")

# # ---------------------------------
# # LOOK UP JOURNALS
# # ---------------------------------
# if (length(unique_dois) > 0) {
#   doi_lookup <- tibble(DOI = unique_dois) |>
#     mutate(`Source title_lookup` = purrr::map_chr(DOI, get_journal_from_doi))
  
#   write_csv(doi_lookup, doi_lookup_csv)
  
#   data_fixed <- left_join(data_fixed, doi_lookup, by = "DOI")
#   data_fixed[["Source title"]] <- dplyr::coalesce(
#     data_fixed[["Source title"]],
#     data_fixed[["Source title_lookup"]]
#   )
#   data_fixed[["Source title_lookup"]] <- NULL
# } else {
#   doi_lookup <- tibble(DOI = character(), `Source title_lookup` = character())
#   write_csv(doi_lookup, doi_lookup_csv)
# }

# # ---------------------------------
# # OPTIONAL: DROP TEMP CSV COLUMNS
# # ---------------------------------
# drop_cols <- c("Year_csv", "DOI_csv", "EID_csv", "Link_csv", "Publisher_csv", "Source_csv", "Title_csv")
# drop_cols <- intersect(drop_cols, names(data_fixed))
# if (length(drop_cols) > 0) {
#   data_fixed <- data_fixed |> select(-all_of(drop_cols))
# }

# # ---------------------------------
# # SAVE
# # ---------------------------------
# saveRDS(data_fixed, out_rds)
# write_csv(data_fixed, out_csv)

# # ---------------------------------
# # SUMMARY
# # ---------------------------------
# cat("Finished.\n")
# cat("Saved RDS to:\n", out_rds, "\n")
# cat("Saved CSV to:\n", out_csv, "\n")
# cat("Saved DOI lookup table to:\n", doi_lookup_csv, "\n")
# cat("Recovered non-missing Year count:", sum(!is.na(data_fixed$Year)), "\n")
# cat("Recovered non-missing Source title count:", sum(!is.na(data_fixed[["Source title"]])), "\n")




# require(tidyverse)

# run_dir <- "D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/embeddings/embs_1000/embs_1000_pca9_1sem_1aut_ref"

# rds_data <- readRDS(file.path(run_dir, "data_cleaned_filtered_tagged_clustered.RDS"))

# csv_data <- readr::read_csv(
#   "D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Mapping_landscape_ABM/Data/data_cleaned_filtered_4_300_YE.csv",
#   show_col_types = FALSE
# )

# # keep the metadata columns you want to bring in
# csv_meta <- csv_data |>
#   transmute(
#     id = as.integer(id),
#     Year = suppressWarnings(readr::parse_number(as.character(Year))),
#     DOI = DOI,
#     EID = EID,
#     Link = Link,
#     Publisher = Publisher,
#     Source = Source,
#     csv_Title = Title
#   )

# data_fixed <- rds_data |>
#   mutate(id = as.integer(id)) |>
#   left_join(csv_meta, by = "id") |>
#   mutate(
#     Year = coalesce(Year.x, Year.y),
#     DOI = coalesce(DOI.x, DOI.y),
#     EID = coalesce(EID.x, EID.y),
#     Link = coalesce(Link.x, Link.y),
#     Publisher = coalesce(Publisher.x, Publisher.y),
#     Source = coalesce(Source.x, Source.y),
#     Title = coalesce(Title, csv_Title)
#   ) |>
#   select(-matches("\\.x$|\\.y$"), -csv_Title)

# saveRDS(data_fixed, file.path(run_dir, "data_cleaned_filtered_tagged_clustered_fixed.RDS"))