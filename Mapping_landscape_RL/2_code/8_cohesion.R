require(tidyverse)
require(ggforce)
require(patchwork)
require(remotes)
Rcpp::sourceCpp("2_code/_helpers.cpp")

remotes::install_github("https://github.com/dwulff/memnet")

data = readRDS("1_data/data_cleaned_filtered_tagged_clustered.RDS")

# GET NETS ------ 

emb = readRDS("1_data/embs/combined_emb.RDS")

combined_net = arma_cosine(emb); combined_net[is.na(combined_net)] = 0
author_net = arma_cosine(emb[,1:384]); author_net[is.na(author_net)] = 0
reference_net = arma_cosine(emb[,(1:384) + 384]); reference_net[is.na(reference_net)] = 0
semantic_net = arma_cosine(emb[,(1:384) + 384*2])

rownames(author_net) = rownames(reference_net) = rownames(semantic_net) = rownames(combined_net) = 
  data$title_id
colnames(author_net) = colnames(reference_net) = colnames(semantic_net) = colnames(combined_net) = 
  data$title_id

cutoffs = c(quantile(author_net[upper.tri(author_net)], .5), 
            quantile(reference_net[upper.tri(reference_net)], .5),
            quantile(semantic_net[upper.tri(semantic_net)]), .5)


# lines = apply(author_net, 1, paste0, collapse=",")
# write_lines(lines, "~/Downloads/author_net.txt")
# 
# lines = apply(reference_net, 1, paste0, collapse=",")
# write_lines(lines, "~/Downloads//citation_net.txt")
# 
# lines = apply(semantic_net, 1, paste0, collapse=",")
# write_lines(lines, "~/Downloads//semantic_net.txt")
# 
# lines = apply(combined_net, 1, paste0, collapse=",")
# write_lines(lines, "~/Downloads//combined_net.txt")
# 
# write_lines(rownames(combined_net), "~/Downloads/row_col_names.txt")

# RUN COHESION ------ 

n_country = length(unique(data$country))

continents = tibble(
  continent = 1:10, 
  order = c(4,9,10,8,6,5,7,3,2,1),
  number = c(1,5,9,2,6,8,10,4,7,3),
  colors = viridis::mako(10, end = .8)[continent[order]],
  colors_white = memnet::cmix(colors, "white", .5),
  colors_white2 = memnet::cmix(colors, "white", .7))

continents = continents %>% 
  mutate(labels = c("Learning\nMechanisms","Neural Reward\nMechanisms",
                    "Attentional Capture","Behavioral\nDecision Making",
                    "Computational\nPsychiatry","Feedback\nProcessing",
                    "Visual Search","Decision\nNeuroscience",
                    "Schizophrenia","Temporal\nDynamics") |> str_replace_all("\n", " "))

cutoff = .5
cutoffs = c(quantile(combined_net[upper.tri(author_net)], cutoff),
            quantile(author_net[upper.tri(author_net)], cutoff), 
            quantile(reference_net[upper.tri(reference_net)], cutoff),
            quantile(semantic_net[upper.tri(semantic_net)], cutoff))

above_cutoff = function(x, cutoff) mean(x > cutoff)
combined_sim = author_sim = reference_sim = semantic_sim = ns = matrix(nrow=n_country,ncol=n_country)
for(i in 1:n_country){
  for(j in 1:n_country){
    
    sel_i = which(data$country == i)  
    sel_j = which(data$country == j)  
    
    if(i == j){
      
      combined_sim[i,j] = above_cutoff(combined_net[sel_i, sel_j][upper.tri(combined_net[sel_i, sel_j])], cutoffs[1])
      author_sim[i,j] = above_cutoff(author_net[sel_i, sel_j][upper.tri(author_net[sel_i, sel_j])], cutoffs[2])
      reference_sim[i,j] = above_cutoff(reference_net[sel_i, sel_j][upper.tri(reference_net[sel_i, sel_j])], cutoffs[3])
      semantic_sim[i,j] = above_cutoff(semantic_net[sel_i, sel_j][upper.tri(semantic_net[sel_i, sel_j])], cutoffs[4])
      ns[i,j] = semantic_net[sel_i, sel_j][upper.tri(semantic_net[sel_i, sel_j])] |> length()
      
    } else {
      
      combined_sim[i,j] = above_cutoff(combined_net[sel_i, sel_j], cutoffs[1])
      author_sim[i,j] = above_cutoff(author_net[sel_i, sel_j], cutoffs[2])
      reference_sim[i,j] = above_cutoff(reference_net[sel_i, sel_j], cutoffs[3])
      semantic_sim[i,j] = above_cutoff(semantic_net[sel_i, sel_j], cutoffs[4])
      ns[i,j] = semantic_net[sel_i, sel_j] |> length()
    }
  }
}

# labels = data |> 
#   select(country, continent) |> 
#   distinct() |> 
#   group_by(continent) |> 
#   mutate(label = paste0(continent, LETTERS[1:n()]))

clusters = data %>% 
  left_join(continents |> select(continent, number)) |> 
  group_by(country, number, continent) %>% 
  summarize(m = mean(Year), mm = median(Year), min = min(Year)) %>% 
  ungroup() %>% 
  arrange(number, mm, min) |> 
  group_by(continent, number) |> 
  mutate(label = paste0(number, LETTERS[1:n()])) |> 
  arrange(number, mm, min) 

centroids = data |> 
  group_by(country) |> 
  summarize(lyt_x = mean(lyt_x),
            lyt_y = mean(lyt_y)) |> 
  left_join(clusters |> select(country, label))

sims_full = expand.grid(country_i = 1:n_country, country_j = 1:n_country) |> 
  as_tibble() |> 
  mutate(combined_sim = c(combined_sim),
         author_sim = c(author_sim),
         reference_sim = c(reference_sim),
         semantic_sim = c(semantic_sim)) |> 
  left_join(centroids, by = c("country_i" = "country")) |> 
  left_join(centroids, by = c("country_j" = "country"),  suffix = c("", "_end")) |> 
  left_join(continents |> select(continent, labels), by = c("continent" = "continent")) |> 
  left_join(continents |> select(continent, labels), by = c("continent_end" = "continent"), suffix = c("","_end")) 
  
sims = sims_full |> 
  filter(country_i < country_j) |> 
  mutate(lyt_x_mid = (lyt_x + lyt_x_end)/2,
         lyt_y_mid = (lyt_y + lyt_y_end)/2 + 2) |> 
  mutate(country = 1)

xs = sims |> 
  pivot_longer(contains("_x"), names_to = "position", values_to = "x") |> 
  select(-contains("_y")) |> 
  mutate(position = factor(position, 
                           levels = c("lyt_x","lyt_x_mid","lyt_x_end"))) |> 
  arrange(position)
ys = sims |> 
  pivot_longer(contains("_y"), names_to = "position", values_to = "y") |> 
  select(-contains("_x")) |> 
  mutate(position = factor(position, 
                           levels = c("lyt_y","lyt_y_mid","lyt_y_end"))) |> 
  arrange(position) 

pos = xs |> bind_cols(ys |> select(y)) |> mutate(id = paste0(country_i, "_", country_j)) |> 
  arrange(id, position)



label_vec = centroids |> pull(label, country)

levels = c("Learning\nMechanisms","Behavioral\nDecision Making", "Temporal\nDynamics", 
           "Decision\nNeuroscience", "Neural Reward\nMechanisms", "Computational\nPsychiatry", "Schizophrenia", "Feedback\nProcessing", 
           "Attentional Capture", "Visual Search") |> str_replace_all("\n", " ")

no_zero = function(sim) as.character(round(sim, 2)) |> str_remove("^0")

p0 = sims_full |> 
  group_by(continent, continent_end) |> 
  summarize(sim = mean(combined_sim),
            labels = first(labels), labels_end = first(labels_end)) |>
  mutate(labels = factor(labels, levels = levels),
         labels_end = factor(labels_end, levels = levels)) |> 
  ggplot(aes(x = labels, y = labels_end, fill = sim, label = no_zero(sim))) +
  geom_tile() + 
  geom_text(col = "white", size=3.3) +
  scale_fill_viridis_c(option = "E", end = .85, limits = c(.09, 1)) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle=45, hjust = 1, size = 8, lineheight = .7),
        axis.text.y = element_text(size = 8, lineheight = .7),
        axis.title = element_blank()) + 
  guides(fill = "none") + 
  labs(title = "Combined") + 
  theme(axis.text.y = element_text(size=12))

p1 = sims_full |> 
  group_by(continent, continent_end) |> 
  summarize(sim = mean(author_sim),
            labels = first(labels), labels_end = first(labels_end)) |>
  mutate(labels = factor(labels, levels = levels),
         labels_end = factor(labels_end, levels = levels)) |> 
  ggplot(aes(x = labels, y = labels_end, fill = sim, label = no_zero(sim))) +
  geom_tile() + 
  geom_text(col = "white", size=3.3) +
  scale_fill_viridis_c(option = "E", end = .85, limits = c(.09, .8)) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle=45, hjust = 1, size = 8, lineheight = .7),
        axis.text.y = element_text(size = 8, lineheight = .7),
        axis.title = element_blank()) + 
  guides(fill = "none") + 
  labs(title = "Author") + 
  theme(axis.text.y = element_blank())

p2 = sims_full |> 
  group_by(continent, continent_end) |> 
  summarize(sim = mean(reference_sim),
            labels = first(labels), labels_end = first(labels_end)) |>
  mutate(labels = factor(labels, levels = levels),
         labels_end = factor(labels_end, levels = levels)) |> 
  ggplot(aes(x = labels, y = labels_end, fill = sim, label = no_zero(sim))) +
  geom_tile() + 
  geom_text(col = "white", size=3.3) +
  scale_fill_viridis_c(option = "E", end = .85, limits = c(.09, 1)) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle=45, hjust = 1, size = 8, lineheight = .7),
        axis.text.y = element_text(size = 8, lineheight = .7),
        axis.title = element_blank()) + 
  guides(fill = "none") + 
  labs(title = "Reference") + 
  theme(axis.text.y = element_blank())

p3 = sims_full |> 
  group_by(continent, continent_end) |> 
  summarize(sim = mean(semantic_sim),
            labels = first(labels), labels_end = first(labels_end)) |>
  mutate(labels = factor(labels, levels = levels),
         labels_end = factor(labels_end, levels = levels)) |> 
  ggplot(aes(x = labels, y = labels_end, fill = sim, label = no_zero(sim))) +
  geom_tile() + 
  geom_text(col = "white", size=3.3) +
  scale_fill_viridis_c(option = "E", end = .85, limits = c(.09, 1)) +
  theme_minimal() +
  theme(axis.text.x = element_text(angle=45, hjust = 1, size = 8, lineheight = .7),
        axis.text.y = element_text(size = 8, lineheight = .7),
        axis.title = element_blank()) + 
  guides(fill = "none") + 
  labs(title = "Semantic") + 
  theme(axis.text.y = element_blank())

p_tiles = p0 + p1 + p2 + p3 + plot_layout(ncol = 4) & guides(size = "none") & 
  theme(axis.text.x = element_text(size=12), plot.title = element_text(hjust = 0.5, size = 16)) 

ggsave("3_figures/1_continent_relations.png", p_tiles, device = "png", dpi =300, width = 16, height = 5.5, units = "in", bg = "white")









cols = data |> 
  arrange(country) |> 
  select(country, continent) |> 
  distinct() |> 
  mutate(col = continents$colors_white[continent]) |> 
  pull(col, country)




p1 = data |> 
  mutate(country = factor(country, levels = as.character(1:30))) |> 
  ggplot(aes(x = lyt_x, y = lyt_y, col = as.factor(country), fill = as.factor(country))) + 
  geom_point(shape = 16, size = 1.5) + 
  theme_void() + 
  guides(col = "none", fill = "none") +
  scale_color_manual(values = cols) +
  scale_x_continuous(expand = c(.05, .15)) +
  scale_y_continuous(expand = c(.05, .05)) +
  geom_point(data = centroids, pch=21, col = "white", fill = "black",
             stroke = .2, size=1.5) +
  geom_text(data = centroids, mapping=aes(label = label), 
            size=3, col = "black", nudge_x = 2) +
  geom_bezier(data = pos |> filter(author_sim > quantile(author_sim, .5)), 
              aes(x = x, y = y, linewidth = author_sim**2, group = id), color = "black") + 
  scale_linewidth(range = c(.0001, .5)) +
  labs(title = "Author similarity") + 
  coord_cartesian(clip="off") +
  guides(size = "none", linewidth="none")

p2 = data |> 
  mutate(country = factor(country, levels = as.character(1:30))) |> 
  ggplot(aes(x = lyt_x, y = lyt_y, col = as.factor(country), fill = as.factor(country))) + 
  geom_point(shape = 16, size = 1.5) + 
  theme_void() + 
  guides(col = "none", fill = "none") +
  scale_color_manual(values = cols) +
  scale_x_continuous(expand = c(.05, .15)) +
  scale_y_continuous(expand = c(.05, .05)) +
  geom_point(data = centroids, pch=21, col = "white", fill = "black",
             stroke = .2, size=1.5) +
  geom_text(data = centroids, mapping=aes(label = label), 
            size=3, col = "black", nudge_x = 2) +
  geom_bezier(data = pos |> filter(reference_sim > quantile(reference_sim, .5)), 
              aes(x = x, y = y, linewidth = reference_sim ** 2, group = id), color = "black") + 
  scale_linewidth(range = c(.0001, .5)) +
  labs(title = "Reference similarity") + 
  coord_cartesian(clip="off") +
  guides(size = "none", linewidth="none")


p3 = data |> 
  mutate(country = factor(country, levels = as.character(1:30))) |> 
  ggplot(aes(x = lyt_x, y = lyt_y, col = as.factor(country), fill = as.factor(country))) + 
  geom_point(shape = 16, size = 1.5) + 
  theme_void() + 
  guides(col = "none", fill = "none") +
  scale_color_manual(values = cols) +
  scale_x_continuous(expand = c(.05, .15)) +
  scale_y_continuous(expand = c(.05, .05)) +
  geom_point(data = centroids, pch=21, col = "white", fill = "black",
             stroke = .2, size=1.5) +
  geom_text(data = centroids, mapping=aes(label = label), 
            size=3, col = "black", nudge_x = 2) +
  geom_bezier(data = pos |> filter(semantic_sim > quantile(semantic_sim, .5)), 
              aes(x = x, y = y, linewidth = semantic_sim**2, group = id), color = "black") + 
  scale_linewidth(range = c(.0001, .5)) +
  labs(title = "Semantic similarity") + 
  coord_cartesian(clip="off") +
  guides(size = "none", linewidth="none")

require(patchwork)
p_relations = p1 + p2 + p3 & theme(plot.title = element_text(hjust = .5))
p_relations



get_dens = function(x,y){
  dens = MASS::kde2d(x, y, n = 101, lims = c(0, 1, 0, 1))
  dens_tbl = expand_grid(x = round(dens$x,2), y = round(dens$y,2)) |> mutate(z = c(t(dens$z)))
  tibble(x, y, x_round = round(x, 2), y_round = round(y, 2)) |> 
    left_join(dens_tbl, by = c("x_round" = "x", "y_round" = "y")) |> 
    pull(z)
  }

label_vec = centroids |> pull(label, country)

p4 = sims |> 
  mutate(id = paste0(label_vec[country_i], "-", label_vec[country_j]),
         same = ifelse(str_sub(label_vec[country_i],1,1) == str_sub(label_vec[country_j],1,1), "Same continent", "Different contents"),
         z = get_dens(author_sim, reference_sim)) |> 
  ggplot(aes(x = author_sim, y = reference_sim, label = id, size = -z**.1, col = same)) +
  geom_text() + 
  theme_minimal() +
  labs(x = "Author similarity", y = "Reference similarity") + 
  scale_size(range = c(.5, 2)) + 
  guides(size = "none") + 
  theme(axis.title.y = element_text(angle = 90, hjust = .5, vjust = 0)) + 
  scale_color_viridis_d(option = "G", end = .7, name = "") + 
  theme(legend.position = "none") +
  annotate("text", x = c(.25, .25), y = c(.35, .37),
           label = c("Different continents", "Same continents"),
           hjust = 0, col = viridis::mako(2, end = .7), fontface = "bold", size=3)

p5 = sims |> 
  mutate(id = paste0(label_vec[country_i], "-", label_vec[country_j]),
         same = ifelse(str_sub(label_vec[country_i],1,1) == str_sub(label_vec[country_j],1,1), "Same continent", "Different contents"),
         z = get_dens(author_sim, semantic_sim)) |> 
  ggplot(aes(x = author_sim, y = semantic_sim, label = id, size = -z**.1, col = same)) +
  geom_text() + 
  theme_minimal() +
  labs(x = "Author similarity", y = "Semantic similarity") +
  scale_size(range = c(.5, 2)) + 
  guides(size = "none")+ 
  scale_color_viridis_d(option = "G", end = .7, name = "") + 
  theme(legend.position = "none") 


p6 = sims |> 
  mutate(id = paste0(label_vec[country_i], "-", label_vec[country_j]),
         same = ifelse(str_sub(label_vec[country_i],1,1) == str_sub(label_vec[country_j],1,1), "Same continent", "Different contents"),
         z = get_dens(reference_sim, semantic_sim)) |> 
  ggplot(aes(x = reference_sim, y = semantic_sim, label = id, size = -z**.1, col = same)) +
  geom_text() + 
  theme_minimal() +
  labs(x = "Reference similarity", y = "Semantic similarity") +
  scale_size(range = c(.5, 2)) + 
  guides(size = "none")+ 
  scale_color_viridis_d(option = "G", end = .7, name = "") + 
  theme(legend.position = "none") 

p_pairs = p4 + p5 + p6 & guides(size = "none")



require(patchwork)
require(ggh4x)
A = ggplot() +
  labs(title = "A") +
  theme(panel.background = element_blank(),
        plot.title = element_text(size=18)) +
  force_panelsizes(rows = unit(0, "in"))

B = ggplot() +
  labs(title = "B") +
  theme(panel.background = element_blank(),
        plot.title = element_text(size=18)) +
  force_panelsizes(rows = unit(0, "in"))

C = ggplot() + 
  labs(title = "C") +
  theme(panel.background = element_blank(),
        plot.title = element_text(size=18)) + 
  force_panelsizes(rows = unit(0, "in"))

p = (
    (A + plot_layout(ncol = 1)) / 
    (p_relations + plot_layout(ncol = 3)) / 
    (B + plot_layout(ncol = 1)) / 
    (p_pairs + plot_layout(ncol = 3))
  ) + 
  plot_layout(heights = c(.005,.5, .005, .5))

ggsave("3_figures/3_cluster_relations.png", p, device = "png", dpi =300, width = 12, height = 8, units = "in", bg = "white")


words = c("I", "am", "hello", "party", "fun", "misery", "apple", "argument", "clean", "stuff", "world", "pottery", "this", "that", "a", "from", "e", "cool")

gen = function() paste0("- ", sample(words, sample(3:6, 1)) |> paste(collapse=" "))
items = sapply(1:1000, function(x) gen())

