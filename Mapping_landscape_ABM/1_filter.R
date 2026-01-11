library(tidyverse)
library(reticulate)
library(glmnet)

use_python(Sys.which("python"), required = TRUE)

run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path("Mapping_landscape_ABM", "Outputs", paste0("filter_run_", run_id))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

log_con <- file(file.path(out_dir, "run.log"), open = "wt")
sink(log_con, split = TRUE)         # console output
sink(log_con, type = "message")     # warnings/errors

cat(sprintf("[%s] Started. out_dir=%s\n", Sys.time(), out_dir)); flush.console()

on.exit({
  cat(sprintf("[%s] Finished.\n", Sys.time())); flush.console()
  sink(type = "message")
  sink()
  close(log_con)
}, add = TRUE)

# non-interactive plotting works on cluster
options(device = "png")

# SBERT
sbert <- reticulate::import("sentence_transformers")
model <- sbert$SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")

# labels
labels <- read_csv("Mapping_landscape_ABM/Data/data_selected_labels_3.csv")

cat(sprintf("[%s] Encoding labels (%d abstracts)...\n", Sys.time(), nrow(labels))); flush.console()
emb <- model$encode(labels$abstract, show_progress_bar = TRUE)
saveRDS(emb, file.path(out_dir, "emb_labels.rds"))
cat(sprintf("[%s] Saved label embeddings.\n", Sys.time())); flush.console()

z <- function(x) (x - mean(x)) / sd(x)
for (i in 1:ncol(emb)) emb[, i] <- z(emb[, i])

# CV
nrun <- 100
lambdas <- exp(seq(-10, 10, 1))
res <- array(dim = c(nrun, length(lambdas), 2))
set.seed(42)

for (i in 1:nrun) {
  cat(sprintf("[%s] CV run %d/%d\n", Sys.time(), i, nrun)); flush.console()
  for (j in 1:length(lambdas)) {
    sel <- sample(nrow(labels), round(nrow(labels) * .8))
    m <- glmnet(emb[sel, ], labels$out_of_scope[sel],
                family = "binomial", alpha = 0, lambda = lambdas[j])
    
    pred_class <- predict(m, newx = emb[-sel, ], type = "class") |> as.integer()
    res[i, j, 1] <- mean(pred_class == labels$out_of_scope[-sel])
    
    pred_prob <- predict(m, newx = emb[-sel, ], type = "response")
    res[i, j, 2] <- -2 * sum(log(pred_prob) * labels$out_of_scope[-sel] +
                               log(1 - pred_prob) * (1 - labels$out_of_scope[-sel]))
  }
}

acc <- colMeans(res[, , 1], na.rm = TRUE)
dev <- colMeans(res[, , 2], na.rm = TRUE)

png(file.path(out_dir, "cv_accuracy.png"), width = 1200, height = 800)
plot(acc, type = "l", xlab = "lambda index", ylab = "Accuracy")
dev.off()

png(file.path(out_dir, "cv_deviance.png"), width = 1200, height = 800)
plot(dev, type = "l", xlab = "lambda index", ylab = "Deviance (-2 loglik)")
dev.off()

write_csv(
  tibble(lambda = lambdas, accuracy = acc, deviance = dev),
  file.path(out_dir, "cv_summary.csv")
)

# refit best model
best_lambda <- lambdas[which.min(dev)]
m <- glmnet(emb, labels$out_of_scope, family = "binomial", alpha = 0, lambda = best_lambda)

# apply
data <- read_csv("Mapping_landscape_ABM/Data/data_cleaned_3.csv")

cat(sprintf("[%s] Encoding full data (%d abstracts)...\n", Sys.time(), nrow(data))); flush.console()
data_emb <- model$encode(data$Abstract_cleaned, show_progress_bar = TRUE)

for(i in 1:ncol(data_emb)) data_emb[,i] <- z(data_emb[,i])
pred_class <- predict(m, newx = data_emb, type = "class") |> as.integer()
data_filtered <- data |> filter(pred_class == 0)
write_csv(data_filtered, file.path(out_dir, "data_cleaned_filtered_3.csv"))

cat(sprintf("[%s] Wrote filtered data: %d/%d rows kept.\n",
            Sys.time(), nrow(data_filtered), nrow(data))); flush.console()