require(tidyverse)
require(xml2)
require(rvest)

#  --------

# read data
data = read_csv("D:/Birmingham_Uni_Oct25/Papers/Mapping_Behav_RL/Vero_ABM/Data/scopus_export_Dec 29-2025_ABM.csv") %>% 
  mutate(Abstract = ifelse(Abstract == "[No abstract available]", NA, Abstract))

# quantify properties
nrow(data) # number of entries
sum(is.na(data$Abstract)) # entries without abstract
sum(is.na(data$References)) # entries without references
sum(is.na(data$`Author(s) ID`)) # entries with incomplete author information
sum(duplicated(data[c("Title", "Source title")])) # duplicate entries
 
data = data %>%
  filter(!is.na(Abstract), 
         !is.na(References),
         !is.na(`Author(s) ID`)) %>% 
  distinct(Title, `Source title`, .keep_all = TRUE) %>%
  mutate(id = 1:n()) %>% 
  select(id, everything())

write_csv(data, "1_data/data.csv")

