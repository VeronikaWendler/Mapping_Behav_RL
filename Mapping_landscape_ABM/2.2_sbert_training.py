from sentence_transformers import SentenceTransformer, InputExample, losses
from torch.utils.data import DataLoader
import pandas as pd
from sklearn.model_selection import train_test_split
import torch
from sklearn.metrics.pairwise import cosine_similarity
import numpy as np
from scipy.stats import pearsonr, spearmanr

def eval(data, model):
    e_1 = model.encode(data["text_i"].values)
    e_2 = model.encode(data["text_j"].values)
    similarities = np.array([
        cosine_similarity([emb1], [emb2])[0][0] 
        for emb1, emb2 in zip(e_1, e_2)
    ])
    return pearsonr(similarities, data["rating_scaled"].values)

# Print evaluation results nicely
def print_eval(data_name, result):
    correlation, p_value = result
    print(f"{data_name} - Pearson correlation: {correlation:.4f}")

# Select device (Apple MPS, CUDA, or CPU)
device = "mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu")
print(f"Using device: {device}")

# Load SentenceTransformer model
#model_name = "sentence-transformers/all-mpnet-base-v2"
model_name = "sentence-transformers/all-MiniLM-L6-v2"
print(f"Loading model: {model_name}")
model = SentenceTransformer(model_name, trust_remote_code=True)
model.to(device)  # Ensure model is on correct device

# Load dataset
data = pd.read_csv("Mapping_landscape_ABM/Data/semantic_training/train_pairs_rating_clean.csv")
print(f"Loaded dataset with {len(data)} rows")

# Print some stats about the rating scores
print(f"Rating range: {data['rating_scaled'].min()} to {data['rating_scaled'].max()}")
print(f"Rating mean: {data['rating_scaled'].mean():.4f}, std: {data['rating_scaled'].std():.4f}")

# Ensure rating scores are floats
context = "An article on behavioral reinforcement learning:\n\n"
data["text_i"] = context + data["text_i"]
data["text_j"] = context + data["text_j"]
data["rating_scaled"] = data["rating_scaled"].astype(float)
print(data)

# Normalize ratings to range 0-1 if they aren't already
# This is important for CosineSimilarityLoss
if data["rating_scaled"].max() > 1.0 or data["rating_scaled"].min() < 0.0:
    print("Normalizing rating scores to range 0-1")
    min_sim = data["rating_scaled"].min()
    max_sim = data["rating_scaled"].max()
    data["rating_scaled"] = (data["rating_scaled"] - min_sim) / (max_sim - min_sim)

# Setting parameters
batch_size = 64 
total_epochs = 5

# EVAL TRAINING ----

# Split into train/test sets
train_data, test_data = train_test_split(data, test_size=0.2, random_state=42)
print(f"Training on {len(train_data)} examples, testing on {len(test_data)} examples")

# Convert DataFrame rows into InputExample format
train_examples = [
    InputExample(texts=[row["text_i"], row["text_j"]], label=float(row["rating_scaled"]))
    for _, row in train_data.iterrows()  # Fixed the syntax error
]

# Print initial evaluation
print("\nInitial evaluation:")
initial_train_result = eval(train_data, model)
initial_test_result = eval(test_data, model)
print_eval("Train", initial_train_result)
print_eval("Test", initial_test_result)

# Use smaller batch size if memory is an issue
train_dataloader = DataLoader(train_examples, shuffle=True, batch_size=batch_size)

# Define the loss function
train_loss = losses.CosineSimilarityLoss(model)

# Set explicit learning rate
warmup_steps = int(len(train_dataloader) * 0.1)  # 10% of steps for warmup

# Train the model with more verbose output
print(f"\nStarting training for {total_epochs} epochs with batch size {batch_size}")
model.fit(
    train_objectives=[(train_dataloader, train_loss)],
    epochs=total_epochs,
    warmup_steps=warmup_steps,
    optimizer_params={'lr': 2e-5},  # Explicitly set learning rate
    show_progress_bar=True,
    #output_path="./trained_model",  # Save the model
    #checkpoint_path="./checkpoints",  # Save checkpoints
    #checkpoint_save_steps=len(train_dataloader),  # Save after each epoch
    #evaluation_steps=len(train_dataloader)  # Evaluate after each epoch
)

# Final evaluation
print("\nFinal evaluation:")
final_train_result = eval(train_data, model)
final_test_result = eval(test_data, model)
print_eval("Train", final_train_result)
print_eval("Test", final_test_result)

# Show improvement
print("\nImprovement:")
train_improvement = final_train_result[0] - initial_train_result[0]
test_improvement = final_test_result[0] - initial_test_result[0]
print(f"Train correlation improved by: {train_improvement:.4f}")
print(f"Test correlation improved by: {test_improvement:.4f}")

# FULL TRAINING ----

# Load SentenceTransformer model
#model_name = "sentence-transformers/all-mpnet-base-v2"
model_name = "sentence-transformers/all-MiniLM-L6-v2"
print(f"Loading model: {model_name}")
model = SentenceTransformer(model_name, trust_remote_code=True)
model.to(device)  # Ensure model is on correct device

# Split into train/test sets
train_data = data
print(f"Training on {len(train_data)} examples")

# Convert DataFrame rows into InputExample format
train_examples = [
    InputExample(texts=[row["text_i"], row["text_j"]], label=float(row["rating_scaled"]))
    for _, row in train_data.iterrows()  # Fixed the syntax error
]

# Use smaller batch size if memory is an issue
train_dataloader = DataLoader(train_examples, shuffle=True, batch_size=batch_size)

# Define the loss function
train_loss = losses.CosineSimilarityLoss(model)

# Set explicit learning rate
warmup_steps = int(len(train_dataloader) * 0.1)  # 10% of steps for warmup

# Train the model with more verbose output
print(f"\nStarting training for {total_epochs} epochs with batch size {batch_size}")
model.fit(
    train_objectives=[(train_dataloader, train_loss)],
    epochs=total_epochs,
    warmup_steps=warmup_steps,
    optimizer_params={'lr': 2e-5},  # Explicitly set learning rate
    show_progress_bar=True,
    #output_path="./trained_model",  # Save the model
    #checkpoint_path="./checkpoints",  # Save checkpoints
    #checkpoint_save_steps=len(train_dataloader),  # Save after each epoch
    #evaluation_steps=len(train_dataloader)  # Evaluate after each epoch
)


print("\nSave model")
model.save("1_data/semantic_training/minilm_ft")










































# import sys, subprocess, importlib

# def ensure(pkg, import_name=None):
#     name = import_name or pkg
#     try:
#         importlib.import_module(name)
#     except ImportError:
#         print(f"Installing missing package: {pkg}", flush=True)
#         subprocess.check_call([sys.executable, "-m", "pip", "install", "-U", pkg, "--no-input"])

# ensure("datasets")
# ensure("accelerate", "accelerate")    
# ensure("pandas")
# ensure("scikit-learn", "sklearn")
# ensure("scipy")
# from sentence_transformers import SentenceTransformer, InputExample, losses
# from torch.utils.data import DataLoader
# import pandas as pd
# from sklearn.model_selection import train_test_split
# import torch
# from sklearn.metrics.pairwise import cosine_similarity
# import numpy as np
# from scipy.stats import pearsonr, spearmanr

# def eval(data, model):
#     e_1 = model.encode(data["text_i"].values)
#     e_2 = model.encode(data["text_j"].values)
#     similarities = np.array([
#         cosine_similarity([emb1], [emb2])[0][0] 
#         for emb1, emb2 in zip(e_1, e_2)
#     ])
#     return pearsonr(similarities, data["rating_scaled"].values)

# # Print evaluation results nicely
# def print_eval(data_name, result):
#     correlation, p_value = result
#     print(f"{data_name} - Pearson correlation: {correlation:.4f}")

# # Select device (Apple MPS, CUDA, or CPU)
# device = "cuda" if torch.cuda.is_available() else "cpu"
# print("Using device:", device)

# # device = "mps" if torch.backends.mps.is_available() else ("cuda" if torch.cuda.is_available() else "cpu")
# # print(f"Using device: {device}")

# # Load SentenceTransformer model
# #model_name = "sentence-transformers/all-mpnet-base-v2"
# model_name = "sentence-transformers/all-MiniLM-L6-v2"
# print(f"Loading model: {model_name}")
# model = SentenceTransformer(model_name, trust_remote_code=True)
# model.to(device)  # Ensure model is on correct device

# # Load dataset
# data = pd.read_csv("Mapping_landscape_ABM/Data/semantic_training/train_pairs_rating_clean.csv")
# print(f"Loaded dataset with {len(data)} rows")

# # Print some stats about the rating scores
# print(f"Rating range: {data['rating_scaled'].min()} to {data['rating_scaled'].max()}")
# print(f"Rating mean: {data['rating_scaled'].mean():.4f}, std: {data['rating_scaled'].std():.4f}")

# # Ensure rating scores are floats
# context = "An article on behavioral reinforcement learning:\n\n"
# data["text_i"] = context + data["text_i"]
# data["text_j"] = context + data["text_j"]
# data["rating_scaled"] = data["rating_scaled"].astype(float)
# print(data.head(3))

# # Normalize ratings to range 0-1 if they aren't already
# # This is important for CosineSimilarityLoss
# if data["rating_scaled"].max() > 1.0 or data["rating_scaled"].min() < 0.0:
#     print("Normalizing rating scores to range 0-1")
#     min_sim = data["rating_scaled"].min()
#     max_sim = data["rating_scaled"].max()
#     data["rating_scaled"] = (data["rating_scaled"] - min_sim) / (max_sim - min_sim)

# # Setting parameters
# batch_size = 32
# total_epochs = 2

# # EVAL TRAINING ----

# # Split into train/test sets
# train_data, test_data = train_test_split(data, test_size=0.2, random_state=42)
# print(f"Training on {len(train_data)} examples, testing on {len(test_data)} examples")

# # Convert DataFrame rows into InputExample format
# train_examples = [
#     InputExample(texts=[row["text_i"], row["text_j"]], label=float(row["rating_scaled"]))
#     for _, row in train_data.iterrows()  # Fixed the syntax error
# ]

# # Print initial evaluation
# print("\nInitial evaluation:")
# initial_train_result = eval(train_data, model)
# initial_test_result = eval(test_data, model)
# print_eval("Train", initial_train_result)
# print_eval("Test", initial_test_result)

# # Use smaller batch size if memory is an issue
# train_dataloader = DataLoader(train_examples, shuffle=True, batch_size=batch_size)

# # Define the loss function
# train_loss = losses.CosineSimilarityLoss(model)

# # Set explicit learning rate
# warmup_steps = int(len(train_dataloader) * 0.1)  # 10% of steps for warmup

# # Train the model with more verbose output
# print(f"\nStarting training for {total_epochs} epochs with batch size {batch_size}")
# model.fit(
#     train_objectives=[(train_dataloader, train_loss)],
#     epochs=total_epochs,
#     warmup_steps=warmup_steps,
#     optimizer_params={'lr': 2e-5},  # Explicitly set learning rate
#     show_progress_bar=True,
#     #output_path="./trained_model",  # Save the model
#     #checkpoint_path="./checkpoints",  # Save checkpoints
#     #checkpoint_save_steps=len(train_dataloader),  # Save after each epoch
#     #evaluation_steps=len(train_dataloader)  # Evaluate after each epoch
# )

# # Final evaluation
# print("\nFinal evaluation:")
# final_train_result = eval(train_data, model)
# final_test_result = eval(test_data, model)
# print_eval("Train", final_train_result)
# print_eval("Test", final_test_result)

# # Show improvement
# print("\nImprovement:")
# train_improvement = final_train_result[0] - initial_train_result[0]
# test_improvement = final_test_result[0] - initial_test_result[0]
# print(f"Train correlation improved by: {train_improvement:.4f}")
# print(f"Test correlation improved by: {test_improvement:.4f}")

# # FULL TRAINING ----

# # Load SentenceTransformer model
# #model_name = "sentence-transformers/all-mpnet-base-v2"
# model_name = "sentence-transformers/all-MiniLM-L6-v2"
# print(f"Loading model: {model_name}")
# model = SentenceTransformer(model_name, trust_remote_code=True)
# model.to(device)  # Ensure model is on correct device

# # Split into train/test sets
# train_data = data
# print(f"Training on {len(train_data)} examples")

# # Convert DataFrame rows into InputExample format
# train_examples = [
#     InputExample(texts=[row["text_i"], row["text_j"]], label=float(row["rating_scaled"]))
#     for _, row in train_data.iterrows()  # Fixed the syntax error
# ]

# # Use smaller batch size if memory is an issue
# train_dataloader = DataLoader(train_examples, shuffle=True, batch_size=batch_size)

# # Define the loss function
# train_loss = losses.CosineSimilarityLoss(model)

# # Set explicit learning rate
# warmup_steps = int(len(train_dataloader) * 0.1)  # 10% of steps for warmup

# # Train the model with more verbose output
# print(f"\nStarting training for {total_epochs} epochs with batch size {batch_size}")
# model.fit(
#     train_objectives=[(train_dataloader, train_loss)],
#     epochs=total_epochs,
#     warmup_steps=warmup_steps,
#     optimizer_params={'lr': 2e-5},  # Explicitly set learning rate
#     show_progress_bar=True,
#     #output_path="./trained_model",  # Save the model
#     #checkpoint_path="./checkpoints",  # Save checkpoints
#     #checkpoint_save_steps=len(train_dataloader),  # Save after each epoch
#     #evaluation_steps=len(train_dataloader)  # Evaluate after each epoch
# )

# print("\nSave model")
# model.save("Mapping_landscape_ABM/Data/semantic_training/minilm_ft")


