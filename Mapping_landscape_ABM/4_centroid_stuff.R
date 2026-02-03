# ==============================================================================
# OBJECTIVE CLUSTER AND CONTINENT DEFINITION FOR SCIENCE MAPS
# ==============================================================================
# Replaces hard-coded continent assignments with data-driven clustering
# ==============================================================================

# Load required libraries
library(tidyverse)
library(dbscan)
library(ggforce)
library(viridis)
library(concaveman)
library(Matrix)


require(remotes)
Rcpp::sourceCpp("Mapping_landscape_ABM/_helpers.cpp")
if (!requireNamespace("memnet", quietly = TRUE)) {
  remotes::install_github("dwulff/memnet")
}
library(memnet)


# ==============================================================================
# 1. LOAD DATA AND CHECK CURRENT STATE
# ==============================================================================

cat("Loading data...\n")
data <- readRDS("/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged_clustered.RDS")

# Check what we have
cat("\n=== DATA SUMMARY ===\n")
cat(sprintf("Total papers: %d\n", nrow(data)))
cat(sprintf("Available columns: %s\n", paste(colnames(data), collapse = ", ")))

# Check if tags are corrupted
if ("tags_clean" %in% colnames(data)) {
  tag_count <- sum(sapply(data$tags_clean, function(x) length(x) > 0))
  cat(sprintf("Papers with non-empty tags: %d (%.1f%%)\n", 
              tag_count, tag_count/nrow(data)*100))
}

# ==============================================================================
# 2. CLEAN AND PREPARE TAGS (HANDLE CORRUPTION)
# ==============================================================================

clean_corrupted_tags <- function(tags_list) {
  # Helper function to clean tags from corrupted LLM outputs
  cleaned <- lapply(tags_list, function(x) {
    if (is.null(x) || length(x) == 0) return(character(0))
    
    # Convert to character if needed
    if (!is.character(x)) {
      x <- as.character(x)
    }
    
    # Remove ERROR messages and empty strings
    x_clean <- x[!grepl("^ERROR|^exception|^status=", x, ignore.case = TRUE)]
    x_clean <- x_clean[x_clean != "" & !is.na(x_clean)]
    
    # Clean up any remaining artifacts
    x_clean <- gsub("Answer=\\[|\\]", "", x_clean)
    x_clean <- str_trim(x_clean)
    x_clean <- x_clean[nchar(x_clean) > 1]  # Remove single characters
    
    return(x_clean)
  })
  
  return(cleaned)
}

# Apply tag cleaning if tags exist
if ("tags_clean" %in% colnames(data)) {
  cat("Cleaning corrupted tags...\n")
  data$tags_clean <- clean_corrupted_tags(data$tags_clean)
  valid_tags <- sum(sapply(data$tags_clean, length) > 0)
  cat(sprintf("Valid tags after cleaning: %d papers\n", valid_tags))
}

# ==============================================================================
# 3. OBJECTIVE CLUSTERING OF COUNTRIES INTO CONTINENTS
# ==============================================================================

# Step 1: Calculate robust centroids for each country cluster
calculate_country_centroids <- function(data) {
  centroids <- data %>%
    group_by(country) %>%
    summarise(
      n_papers = n(),
      centroid_x = median(lyt_x, na.rm = TRUE),  # Use median for robustness
      centroid_y = median(lyt_y, na.rm = TRUE),
      centroid_x_mean = mean(lyt_x, na.rm = TRUE),
      centroid_y_mean = mean(lyt_y, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    filter(n_papers >= 5)  # Remove very small clusters
  
  return(centroids)
}

# Step 2: Determine optimal number of continents using multiple methods
determine_optimal_k <- function(centroids, max_k = 15) {
  # Prepare data for clustering
  coords <- centroids %>% select(centroid_x, centroid_y) %>% as.matrix()
  
  # Method 1: Elbow method (within-cluster sum of squares)
  wss <- sapply(1:max_k, function(k) {
    kmeans(coords, centers = k, nstart = 25)$tot.withinss
  })
  
  # Method 2: Silhouette method
  require(cluster)
  silhouette_scores <- sapply(2:max_k, function(k) {
    clustering <- kmeans(coords, centers = k, nstart = 25)$cluster
    if (length(unique(clustering)) < k) return(0)
    mean(silhouette(clustering, dist(coords))[, 3])
  })
  
  # Method 3: Gap statistic (more robust but slower)
  gap_stat <- clusGap(coords, FUN = kmeans, K.max = max_k, B = 50, nstart = 25)
  
  # Combine evidence
  elbow_k <- which.min(abs(diff(diff(wss)) / diff(wss)[-1]))
  silhouette_k <- which.max(silhouette_scores) + 1
  gap_k <- maxSE(gap_stat$Tab[, "gap"], gap_stat$Tab[, "SE.sim"])
  
  # Choose k (prefer silhouette if reasonable, otherwise gap)
  optimal_k <- if (silhouette_scores[silhouette_k - 1] > 0.5) {
    silhouette_k
  } else {
    gap_k
  }
  
  # Ensure reasonable bounds
  optimal_k <- min(max(optimal_k, 5), 12)
  
  cat(sprintf("\n=== OPTIMAL K DETERMINATION ===\n"))
  cat(sprintf("Elbow method suggests: %d\n", elbow_k))
  cat(sprintf("Silhouette method suggests: %d (score: %.3f)\n", 
              silhouette_k, silhouette_scores[silhouette_k - 1]))
  cat(sprintf("Gap statistic suggests: %d\n", gap_k))
  cat(sprintf("Selected optimal k: %d\n", optimal_k))
  
  return(optimal_k)
}

# Step 3: Perform hierarchical clustering on country centroids
cluster_countries_into_continents <- function(data) {
  # Calculate centroids
  centroids <- calculate_country_centroids(data)
  
  # Determine optimal number of continents
  optimal_k <- determine_optimal_k(centroids)
  
  # Perform hierarchical clustering
  hc <- hclust(dist(centroids[, c("centroid_x", "centroid_y")]), 
               method = "ward.D2")
  
  # Cut tree at optimal k
  continent_assignments <- cutree(hc, k = optimal_k)
  centroids$continent_new <- continent_assignments
  
  # Join back to original data
  data_with_continents <- data %>%
    select(-any_of("continent")) %>%
    left_join(centroids %>% select(country, continent_new), by = "country") %>%
    rename(continent = continent_new)
  
  # For countries not in centroids (too small), assign to nearest continent
  missing_countries <- unique(data$country[!data$country %in% centroids$country])
  if (length(missing_countries) > 0) {
    cat(sprintf("Assigning %d small countries to nearest continent...\n", 
                length(missing_countries)))
    
    for (country_id in missing_countries) {
      # Get mean coordinates of this country
      country_coords <- data %>%
        filter(country == country_id) %>%
        summarise(mean_x = mean(lyt_x), mean_y = mean(lyt_y))
      
      # Find nearest continent centroid
      distances <- sqrt(
        (centroids$centroid_x - country_coords$mean_x)^2 +
        (centroids$centroid_y - country_coords$mean_y)^2
      )
      nearest_continent <- centroids$continent_new[which.min(distances)]
      
      # Assign
      data_with_continents$continent[data_with_continents$country == country_id] <- nearest_continent
    }
  }
  
  return(list(data = data_with_continents, centroids = centroids))
}

# ==============================================================================
# 4. DATA-DRIVEN LABEL GENERATION
# ==============================================================================

generate_continent_labels <- function(data, centroids, 
                                      use_tags = TRUE, 
                                      use_titles = TRUE,
                                      use_keywords = TRUE) {
  
  labels_df <- centroids %>%
    select(continent_new, centroid_x, centroid_y) %>%
    rename(continent = continent_new) %>%
    distinct()
  
  # Option 1: Labels from tags (if available and usable)
  if (use_tags && "tags_clean" %in% colnames(data)) {
    tag_labels <- data %>%
      # Filter papers with valid tags
      filter(sapply(tags_clean, function(x) length(x) > 0)) %>%
      unnest(tags_clean) %>%
      filter(!is.na(tags_clean), tags_clean != "", nchar(tags_clean) > 2) %>%
      # Count tags per continent
      count(continent, tags_clean, sort = TRUE) %>%
      group_by(continent) %>%
      # Get top tags, weighted by frequency
      slice_max(n, n = 5) %>%
      summarise(
        top_tags = paste(head(tags_clean, 3), collapse = ", "),
        tag_diversity = n_distinct(tags_clean),
        .groups = "drop"
      )
    
    labels_df <- labels_df %>% left_join(tag_labels, by = "continent")
  }
  
  # Option 2: Labels from representative titles
  if (use_titles && "Title" %in% colnames(data)) {
    title_labels <- data %>%
      # Find papers closest to each continent centroid
      left_join(labels_df %>% select(continent, centroid_x, centroid_y), 
                by = "continent") %>%
      mutate(
        dist_to_centroid = sqrt((lyt_x - centroid_x)^2 + (lyt_y - centroid_y)^2)
      ) %>%
      group_by(continent) %>%
      arrange(dist_to_centroid) %>%
      slice_head(n = 3) %>%
      summarise(
        representative_titles = paste(
          str_trunc(Title, width = 60), 
          collapse = "\n"
        ),
        .groups = "drop"
      )
    
    labels_df <- labels_df %>% left_join(title_labels, by = "continent")
  }
  
  # Option 3: Labels from author keywords (if available)
  if (use_keywords && "Author Keywords" %in% colnames(data)) {
    keyword_labels <- data %>%
      mutate(
        keywords_clean = str_split(`Author Keywords`, ";") %>%
          map(str_trim) %>%
          map(function(x) x[x != "" & nchar(x) > 2])
      ) %>%
      filter(sapply(keywords_clean, length) > 0) %>%
      unnest(keywords_clean) %>%
      count(continent, keywords_clean, sort = TRUE) %>%
      group_by(continent) %>%
      slice_max(n, n = 3) %>%
      summarise(
        top_keywords = paste(keywords_clean, collapse = ", "),
        .groups = "drop"
      )
    
    labels_df <- labels_df %>% left_join(keyword_labels, by = "continent")
  }
  
  # Create final labels based on available data
  labels_df <- labels_df %>%
    mutate(
      # Try tags first, then keywords, then titles
      label = case_when(
        !is.na(top_tags) & nchar(top_tags) > 5 ~ 
          paste0(str_trunc(top_tags, 40), "..."),
        !is.na(top_keywords) & nchar(top_keywords) > 5 ~ 
          paste0(str_trunc(top_keywords, 40), "..."),
        !is.na(representative_titles) ~ 
          paste("Region", continent),
        TRUE ~ paste("Region", continent)
      ),
      # Simple numeric label for plotting
      label_simple = paste("Region", continent),
      # Descriptive label for tables
      label_descriptive = case_when(
        !is.na(top_tags) ~ paste("Region", continent, ":", top_tags),
        !is.na(top_keywords) ~ paste("Region", continent, ":", top_keywords),
        TRUE ~ paste("Region", continent)
      )
    )
  
  return(labels_df)
}

# ==============================================================================
# 5. CREATE OBJECTIVE SCIENCE MAP
# ==============================================================================

create_objective_science_map <- function(data, labels_df, 
                                         output_file = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/objective_cluster_map.png") {
  
  # Prepare data for visualization
  set.seed(42)
  data_viz <- data %>%
    mutate(
      lyt_x_jit = lyt_x + rnorm(n(), sd = 0.15),
      lyt_y_jit = lyt_y + rnorm(n(), sd = 0.15)
    )
  
  # Color palette
  n_continents <- length(unique(data$continent))
  continent_colors <- viridis::mako(n_continents, end = 0.85)
  names(continent_colors) <- as.character(1:n_continents)
  
  # Calculate label positions (avoid overlaps)
  label_positions <- data_viz %>%
    group_by(continent) %>%
    summarise(
      lyt_x = median(lyt_x),
      lyt_y = median(lyt_y),
      n_papers = n(),
      .groups = "drop"
    ) %>%
    left_join(labels_df, by = "continent") %>%
    arrange(desc(n_papers))  # Larger regions get placed first
  
  # Simple overlap avoidance
  for (i in 2:nrow(label_positions)) {
    for (j in 1:(i-1)) {
      dx <- label_positions$lyt_x[i] - label_positions$lyt_x[j]
      dy <- label_positions$lyt_y[i] - label_positions$lyt_y[j]
      dist <- sqrt(dx^2 + dy^2)
      
      if (dist < 2) {  # Too close
        # Adjust position
        angle <- atan2(dy, dx)
        label_positions$lyt_x[i] <- label_positions$lyt_x[i] + 0.5 * cos(angle + pi/2)
        label_positions$lyt_y[i] <- label_positions$lyt_y[i] + 0.5 * sin(angle + pi/2)
      }
    }
  }
  
  # Create the plot
  p <- ggplot(data_viz, aes(x = lyt_x, y = lyt_y)) +
    
    # Add convex hulls for each continent
    ggforce::geom_mark_hull(
      aes(fill = factor(continent), color = factor(continent)),
      alpha = 0.15, 
      expand = unit(3, "mm"),
      radius = unit(3, "mm"),
      size = 0.5
    ) +
    
    # Add all papers as background
    geom_point(
      aes(x = lyt_x_jit, y = lyt_y_jit),
      color = "gray80", alpha = 0.2, size = 0.8
    ) +
    
    # Add continent-colored points
    geom_point(
      aes(x = lyt_x_jit, y = lyt_y_jit, color = factor(continent)),
      alpha = 0.6, size = 1.2
    ) +
    
    # Add labels
    geom_label(
      data = label_positions,
      aes(x = lyt_x, y = lyt_y, label = label_simple, fill = factor(continent)),
      color = "white", 
      size = 3.5,
      fontface = "bold",
      alpha = 0.85,
      label.size = 0.5,
      label.padding = unit(0.3, "lines")
    ) +
    
    # Add continent centroids
    geom_point(
      data = label_positions,
      aes(x = lyt_x, y = lyt_y),
      color = "white", 
      size = 3, 
      shape = 21, 
      stroke = 1,
      fill = "transparent"
    ) +
    
    # Styling
    scale_color_manual(values = continent_colors) +
    scale_fill_manual(values = continent_colors) +
    theme_void() +
    theme(
      legend.position = "none",
      plot.background = element_rect(fill = "white", color = NA),
      plot.margin = margin(20, 20, 20, 20),
      panel.background = element_rect(fill = "white", color = NA)
    ) +
    coord_fixed() +
    labs(
      title = "Agent-Based Modeling Research Landscape",
      subtitle = paste("Thematic regions identified through hierarchical clustering of", 
                      nrow(data), "papers")
    ) +
    theme(
      plot.title = element_text(hjust = 0.5, face = "bold", size = 16),
      plot.subtitle = element_text(hjust = 0.5, size = 12, color = "gray40")
    )
  
  # Save the plot
  ggsave(
    output_file,
    plot = p,
    width = 10,
    height = 8,
    dpi = 300,
    bg = "white"
  )
  
  cat(sprintf("\nMap saved to: %s\n", output_file))
  
  return(p)
}

# ==============================================================================
# 6. GENERATE SUPPORTING ANALYTICS AND TABLES
# ==============================================================================

generate_analytics <- function(data, labels_df, centroids) {
  
  # Summary statistics - CHECK COLUMN NAME
  continent_summary <- data %>%
    group_by(continent) %>%
    summarise(
      n_papers = n(),
      n_countries = n_distinct(country),
      # Try different possible column names
      avg_year = ifelse("Year" %in% colnames(data), 
                       mean(Year, na.rm = TRUE),
                       ifelse("year" %in% colnames(data),
                             mean(year, na.rm = TRUE),
                             NA)),
      year_range = ifelse("Year" %in% colnames(data),
                         paste(min(Year, na.rm = TRUE), "-", max(Year, na.rm = TRUE)),
                         ifelse("year" %in% colnames(data),
                               paste(min(year, na.rm = TRUE), "-", max(year, na.rm = TRUE)),
                               "N/A")),
      density = n() / (sd(lyt_x, na.rm = TRUE) * sd(lyt_y, na.rm = TRUE)),
      .groups = "drop"
    ) %>%
    left_join(labels_df, by = "continent") %>%
    arrange(desc(n_papers)) %>%
    mutate(
      continent_id = row_number(),
      percent = round(n_papers / sum(n_papers) * 100, 1)
    ) %>%
    select(continent_id, continent, n_papers, percent, n_countries, 
           label_descriptive, everything())
  
  # Country-to-continent mapping
  country_mapping <- data %>%
    group_by(country, continent) %>%
    summarise(n_papers = n(), .groups = "drop") %>%
    arrange(continent, desc(n_papers))
  
  write_csv(continent_summary, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/continent_summary.csv")
  write_csv(country_mapping, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/country_to_continent_mapping.csv")
  
  cat("\n=== ANALYTICS SUMMARY ===\n")
  print(continent_summary %>% select(continent_id, n_papers, percent, label_descriptive))
  
  return(list(
    summary = continent_summary,
    mapping = country_mapping
  ))
}

# ==============================================================================
# 7. MAIN EXECUTION PIPELINE
# ==============================================================================

main <- function() {
  cat(strrep("=", 60), "\n")
  cat("OBJECTIVE CONTINENT DEFINITION FOR SCIENCE MAPS\n")
  cat(strrep("=", 60), "\n\n")
  
  # Step 1: Cluster countries into continents
  cat("Step 1: Clustering countries into continents...\n")
  clustering_result <- cluster_countries_into_continents(data)
  data_with_continents <- clustering_result$data
  centroids <- clustering_result$centroids
  
  cat(sprintf("Created %d objective continents from %d countries\n",
              length(unique(data_with_continents$continent)),
              length(unique(data_with_continents$country))))
  
  # Step 2: Generate data-driven labels
  cat("\nStep 2: Generating continent labels...\n")
  labels_df <- generate_continent_labels(
    data_with_continents, 
    centroids,
    use_tags = TRUE,
    use_titles = TRUE,
    use_keywords = TRUE
  )
  
  cat("Generated labels for all continents\n")
  print(labels_df %>% select(continent, label))
  
  # Step 3: Create the science map
  cat("\nStep 3: Creating science map visualization...\n")
  map_plot <- create_objective_science_map(
    data_with_continents,
    labels_df,
    output_file = "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/objective_science_map.png"
  )
  
  # Step 4: Generate analytics
  cat("\nStep 4: Generating analytics and summary tables...\n")
  analytics <- generate_analytics(data_with_continents, labels_df, centroids)
  
  # Step 5: Save updated data
  cat("\nStep 5: Saving updated dataset...\n")
  saveRDS(data_with_continents, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged_clustered_objective.RDS")
  write_csv(data_with_continents, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/data_cleaned_filtered_tagged_clustered_objective.csv")
  
  cat("\n=== COMPLETION SUMMARY ===\n")
  cat(sprintf("1. Created %d objective continents\n", 
              length(unique(data_with_continents$continent))))
  cat(sprintf("2. Mapped %d countries to continents\n", 
              length(unique(data_with_continents$country))))
  cat(sprintf("3. Generated labeled map: /rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/objective_science_map.png\n"))
  cat(sprintf("4. Saved analytics tables\n"))
  cat(sprintf("5. Saved updated data with objective continents\n"))
  
  return(list(
    data = data_with_continents,
    plot = map_plot,
    labels = labels_df,
    analytics = analytics
  ))
}

# ==============================================================================
# 8. RUN THE PIPELINE
# ==============================================================================

# Execute the pipeline
result <- main()

# Optional: Create a simple interactive version
if (interactive()) {
  library(plotly)
  simple_plot <- result$data %>%
    sample_n(min(1000, nrow(result$data))) %>%
    ggplot(aes(x = lyt_x, y = lyt_y, color = factor(continent), 
               text = paste("Title:", str_trunc(Title, 100)))) +
    geom_point(alpha = 0.6) +
    theme_void() +
    theme(legend.position = "none")
  
  interactive_plot <- ggplotly(simple_plot, tooltip = "text")
  htmlwidgets::saveWidget(interactive_plot, "/rds/projects/z/zhanglp-vwendler-core/ABM_Mapping/Data/embs_300/interactive_map.html")
}

cat("\n", strrep("=", 60), "\n", sep="")
cat("OBJECTIVE CONTINENT DEFINITION COMPLETE\n")
cat(strrep("=", 60), "\n") #