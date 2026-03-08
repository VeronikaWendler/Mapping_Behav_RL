require(tidyverse)
require(dbscan)
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
data = readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/data_cleaned_filtered_tagged_clustered.RDS")

clusters = data |>
  select(id, lyt_x, lyt_y, country) |>
  distinct() |>
  mutate(
    id = as.integer(id),
    continent = case_when(
      country %in% c(1, 11, 30) ~ 1,
      country %in% c(2, 3, 7, 15, 17, 23, 27) ~ 2,
      country %in% c(5, 6, 9, 10, 16, 18, 20, 22, 29) ~ 3,
      country %in% c(4, 13, 24, 28) ~ 4,
      country %in% c(8, 19, 21, 26) ~ 5,
      country %in% c(12, 14, 25) ~ 6,
      TRUE ~ NA_real_
    )
  )

data = data |>
  select(-any_of("continent")) |>
  left_join(clusters |> select(id, continent), by = "id")

print(data |> count(continent, sort = TRUE))
print(data |> count(country, continent, sort = TRUE))

saveRDS(
  data,
  "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_1000/data_cleaned_filtered_tagged_clustered_v2.RDS"
)