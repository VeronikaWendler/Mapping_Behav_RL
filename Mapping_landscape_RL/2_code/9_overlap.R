require(tidyverse)
require(tidytext)
require(patchwork)
require(ggh4x)


data = readRDS("1_data/data_cleaned_filtered_tagged_clustered.RDS")

tag_vec = data |> pull(tags_clean) |> unlist() 
tags = tibble(tag = tag_vec) |> count(tag) |> arrange(desc(n)) |> print(n = 100)

get_entr = function(tag){
  entr = function(x) {p = x/sum(x); -sum(p*log(p))}
  pos = sapply(data$tags_clean, function(tags) tag %in% tags)
  cntry = table(data$continent[pos])[as.character(1:10)]
  cntry[is.na(cntry)] = 0
  entr(cntry + .1)
}

tags = tags  |> 
  filter(n >= 20) |> 
  mutate(entropy = sapply(tag, get_entr))

tags_sel = tags |> 
  arrange(desc(n)) |> 
  slice(1:60)

p_tags = tags |> 
  ggplot(aes(x = n, y = entropy, label = tag, size = n)) + 
  geom_point(mapping = aes(col = tag %in% tags_sel$tag)) +
  scale_color_manual(values = grey(c(.85, .5))) + 
  ggrepel::geom_text_repel(data = tags_sel,
                           max.overlaps = 50,
                           segment.size=.2,
                           min.segment.length = 0,
                           fontface = 1) +
  theme_minimal() + 
  guides(col = "none") + 
  scale_x_continuous(trans = "log", 
                     breaks = c(50, 400, 3000),
                     limits = c(20, 3000), expand = c(.1, .1, .1, .1)) +
  labs(x = "Number of articles (log)",
       y = "Continent entropy") +
  guides(size = "none")
p_tags


n_cluster = length(unique(data$continent))
continents = tibble(
  continent = 1:10, 
  order = c(4,9,10,8,6,5,7,3,2,1),
  colors = viridis::mako(10, end = .8)[continent[order]],
  colors_white = memnet::cmix(colors, "white", .5),
  colors_white2 = memnet::cmix(colors, "white", .7))

set.seed(42)
x_jitter = diff(range(data$lyt_x)) * .01
y_jitter = diff(range(data$lyt_y)) * .01
data = data %>% 
  mutate(lyt_x_jit = lyt_x + rnorm(n(),sd = x_jitter),
         lyt_y_jit = lyt_y + rnorm(n(),sd = y_jitter))

for(i in 1:nrow(tags_sel)){
  
  tag = tags_sel$tag[i]
  found = sapply(data$tags_clean, function(x) tag %in% x)
  
  diff(range(data$lyt_x))
  tmp = data |> 
    ggplot(aes(x = lyt_x, y = lyt_y, 
               col = as.factor(continent), fill = as.factor(continent))) + 
    geom_point(shape = 16, size = 1) + 
    geom_point(data = data %>% filter(found),
               aes(x = lyt_x_jit, y = lyt_y_jit),
               col = "white", fill = viridis::rocket(1, begin = .55), pch=21, 
               stroke=0, size=.8, alpha = .4) + 
    theme_void() + 
    guides(col = "none", fill = "none") +
    scale_color_manual(values = continents$colors %>% 
                         embedR:::cmix(rep("white", n_cluster), rep(.8, n_cluster))) +
    scale_x_continuous(expand = c(.05, .15)) +
    scale_y_continuous(expand = c(.05, .05)) +
    #geom_segment(data = labels, aes(xend = lyt_x_end, yend = lyt_y_end), size=.1, linetype=1) + 
    # geom_label(data = labels %>% mutate(topic = str_wrap(topic, 15)), aes(label = topic), size = 1, 
    #            nudge_x = nudge_x, nudge_y = nudge_y, lineheight = .7, fontface="bold", fill = "white", 
    #            label.r = unit(.15, "lines"), label.padding = unit(.1, "lines"), alpha=1,label.size=0) +
    scale_size(range = c(.01, 2)) +
    labs(title = str_replace(tag, " ", "\n")) +
    theme(plot.title = element_text(hjust = .5, size = 9)) 
  tmp
  if(i == 1) p_topic = tmp else p_topic = p_topic + tmp
  
}


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

p = (A + plot_layout(ncol = 1))/
  (p_tags + plot_layout(ncol = 1)) /
  (B + plot_layout(ncol = 1)) / 
  (p_topic + plot_layout(ncol = 10)) + 
  plot_layout(heights = c(.005,.35,.005,.7))

ggsave("3_figures/4_cluster_topics.png", p, device = "png", dpi =300, width = 12, height = 12, units = "in", bg = "white")

