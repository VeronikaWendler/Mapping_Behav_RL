require(tidyverse)
require(ggforce)
require(patchwork)
require(remotes)
Rcpp::sourceCpp("2_code/_helpers.cpp")

remotes::install_github("https://github.com/dwulff/memnet")

data = readRDS("1_data/data_cleaned_filtered_tagged_clustered.RDS")
write_csv(data |> rename(cluster = continent), "~/Downloads/data.csv")

auth = data |> select(`Author(s) ID`, `Author full names`, `Authors`)

ids = str_split(auth$`Author(s) ID`, ";") |> unlist() |> str_squish()
full = str_split(auth$`Author full names`, ";") |> unlist() |> str_squish() |> str_remove("[:digit:]+") |> str_remove("\\(") |> str_remove("\\)")
last = str_split(full, ",") |> sapply(function(x) x[1]) |> str_squish()
first = str_split(full, ",") |> sapply(function(x) x[2]) |> str_squish()
full = paste(first, last)

authors = tibble(ids, full, last, first) |> filter(!duplicated(ids))
write_csv(authors, "~/Downloads/authors.csv")


centroids = data %>% 
  group_by(continent) %>% 
  summarize(lyt_x = mean(lyt_x),
            lyt_y = mean(lyt_y)) %>% 
  mutate(lyt_x_end = lyt_x + c(-3,0,0,-5,3,3,-1,-2,0,-2)*1.5,
         lyt_y_end = lyt_y + c(7,6,3,0,-8,-1,1,11,3,0)*1.5, 
         adj = c(.5, .5, .5, 1, .5, 0, 1, .5, .5, 1))

clusters = continents %>% left_join(centroids) %>% 
  mutate(labels = c("Probabilistic\nLearning","Neural Reward\nMechanisms",
                    "Attentional Capture","Behavioral\nDecision\nMaking",
                    "Computational\nPsychiatry","Feedback\nProcessing",
                    "Visual Search","Decision\nNeuroscience",
                    "Psychopathology","Temporal\nDynamics")) |> 
  rename(cluster = continent, topic = labels, color = colors, fill = colors_white) |> 
  select(cluster, lyt_x, lyt_y, lyt_x_end, lyt_y_end, topic, color, fill)

write_csv(clusters, "~/Downloads/clusters.csv")

