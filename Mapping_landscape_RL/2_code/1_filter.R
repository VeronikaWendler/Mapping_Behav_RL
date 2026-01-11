library(tidyverse)
library(reticulate)
library(glmnet)

use_python(Sys.which("python"), required = TRUE)

# output directories
run_id <- format(Sys.time(), "%Y%m%d_%H%M%S")
out_dir <- file.path("Mapping_landscape_ABM", "Outputs", paste0("filter_run_", run_id))
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

fig_dir <- file.path(out_dir, "figures")
dir.create(fig_dir, recursive = TRUE, showWarnings = FALSE)

log_file <- file.path(out_dir, "run.log")
log_con <- file(log_file, open = "wt")
sink(log_con, split = TRUE)            # send console output
sink(log_con, type = "message")        # send warnings/errors

cat(sprintf("[%s] Started. out_dir=%s\n", Sys.time(), out_dir)); flush.console()

on.exit({
  cat(sprintf("[%s] Finished.\n", Sys.time())); flush.console()
  sink(type = "message")
  sink()
  close(log_con)
}, add = TRUE)

options(device = "png")


sbert = import("sentence_transformers")
model = sbert$SentenceTransformer("sentence-transformers/all-MiniLM-L6-v2")

# ---

labels <- read_csv("Mapping_landscape_ABM/Data/data_selected_labels_3.csv")

emb = model$encode(labels$abstract)

cat(sprintf("[%s] Encoding labels (%d abstracts)...\n", Sys.time(), nrow(labels))); flush.console()
emb <- model$encode(labels$abstract, show_progress_bar = TRUE)
saveRDS(emb, file.path(out_dir, "emb_labels.rds"))
cat(sprintf("[%s] Saved label embeddings.\n", Sys.time())); flush.console()

z = function(x) (x - mean(x))/sd(x)
for(i in 1:ncol(emb)) emb[,i] = z(emb[,i])


nrun = 100
lambdas = exp(seq(-10, 10, 1))
res = array(dim = c(nrun, length(lambdas), 2))
set.seed(42)
for(i in 1:nrun){
  print(i)
  for(j in 1:length(lambdas)){
    sel = sample(nrow(labels), round(nrow(labels)*.8))
    m = glmnet(emb[sel,], labels$out_of_scope[sel], family = "binomial", alpha = 0, lambda = lambdas[j])
    pred = predict(m, newx = emb[-sel,], type = "class") |> as.integer()
    res[i, j, 1] = mean(pred == labels$out_of_scope[-sel])
    pred = predict(m, newx = emb[-sel,], type = "response")
    res[i, j, 2] = -2*sum(log(pred) * labels$out_of_scope[-sel] + log(1-pred) * (1-labels$out_of_scope[-sel]))
    }
  }

acc <- colMeans(res[,,1], na.rm = TRUE)
dev <- colMeans(res[,,2], na.rm = TRUE)
png(file.path(fig_dir, "cv_accuracy.png"), width = 1200, height = 800)
plot(acc, type = "l", xlab = "lambda index", ylab = "Accuracy")
dev.off()
png(file.path(fig_dir, "cv_deviance.png"), width = 1200, height = 800)
plot(dev, type = "l", xlab = "lambda index", ylab = "Deviance (-2 loglik)")
dev.off()
# save the numeric values
write_csv(tibble(lambda = lambdas, accuracy = acc, deviance = dev),
          file.path(out_dir, "cv_summary.csv"))


# RERUN ----

best_lambda = lambdas[which.min(colMeans(res[,,2]))]
m = glmnet(emb, labels$out_of_scope, family = "binomial", alpha = 0, lambda = best_lambda)

# APPLY ----

data = read_csv("Mapping_landscape_ABM/Data/data_cleaned_3.csv")

data_emb = model$encode(data$Abstract_cleaned)
for(i in 1:ncol(data_emb)) data_emb[,i] = z(data_emb[,i])

label = predict(m, newx = data_emb, type = "class") |> as.integer()
label = predict(m, newx = data_emb, type = "response") 

data_filtered = data |> filter(label == 0)

write_csv(data_filtered, "Mapping_landscape_ABM/Data/data_cleaned_filtered_3.csv")
