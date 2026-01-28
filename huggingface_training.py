# space for training 

# the pipeline is super important as it connects a model with it's preprocessing and postprocessing steps

#%%
# Example 1: positive and negative classification ------------------------------------------
from transformers import pipeline

classifier = pipeline("sentiment-analysis")
#classifier("I've been waiting for a HuggingFace course my whole life.")


classifier(
    ["I've been waiting for a HuggingFace course my whole life.", "I hate this so much!"]
)


#%%
# Example 2: zero-shot-classification for unlabeled texts ------------------------------------
from transformers import pipeline

classifier = pipeline("zero-shot-classification")
classifier(
    "This is a course about the Transformers library",
    candidate_labels=["education", "politics", "business"],
)


# %%
# Example 3: Using text generation -----------------------------------------------------------------

from transformers import pipeline

generator = pipeline("text-generation")
generator("In this course, we will teach you how to", 
          num_return_sequences=2,
          max_length=15)

# %%
# Example 4: Using any model from the hub in a pipeline --------------------------------------------------
from transformers import pipeline

generator = pipeline("text-generation", model="HuggingFaceTB/SmolLM2-360M")
generator(
    "In this course, we will teach you how to",
    max_length=30,
    num_return_sequences=2,
)
# %%
### Hugging Face's Inference Providers 
# Hugging Face’s Inference Providers give developers access to hundreds of machine learning models, powered by world-class inference providers
# platform integrates with leading AI infrastructure providers, giving you access to their specialized capabilities through a single, consistent AP
# An inference provider is the system that hosts a trained language model and executes forward passes on user prompts,
#  handling performance, scaling, and delivery of generated outputs via an API

# Example 5: Fill in the blanks -----------------------------------------------------------------------------------

from transformers import pipeline

unmasker = pipeline("fill-mask")
unmasker("This course will teach you all about <mask> models.", top_k=2)

# %%
#top_k argument controls how many possibilities you want to be displayed
# same with BERT

from transformers import pipeline

unmasker = pipeline("fill-mask", model="bert-base-cased")
unmasker("This course will teach you all about [MASK] models.", top_k=2)
 
# --> we can see that BERT gives us different responses
# %%
# Example 6: named entity recognition --------------------------------------------------

from transformers import pipeline

ner = pipeline("ner", grouped_entities=True)
ner("My name is Sylvain and I work at Hugging Face in Brooklyn.")

# %%
# Example 7: Question Answering ----------------------------------------------

from transformers import pipeline

question_answerer = pipeline("question-answering")
question_answerer(
    question="Where do I work?",
    context="My name is Sylvain and I work at Hugging Face in Brooklyn",
)
# %%
# Example 8: Summarization ----------------------------------------------
from transformers import pipeline

summarizer = pipeline("summarization")
summarizer(
    """
    America has changed dramatically during recent years. Not only has the number of 
    graduates in traditional engineering disciplines such as mechanical, civil, 
    electrical, chemical, and aeronautical engineering declined, but in most of 
    the premier American universities engineering curricula now concentrate on 
    and encourage largely the study of engineering science. As a result, there 
    are declining offerings in engineering subjects dealing with infrastructure, 
    the environment, and related issues, and greater concentration on high 
    technology subjects, largely supporting increasingly complex scientific 
    developments. While the latter is important, it should not be at the expense 
    of more traditional engineering.

    Rapidly developing economies such as China and India, as well as other 
    industrial countries in Europe and Asia, continue to encourage and advance 
    the teaching of engineering. Both China and India, respectively, graduate 
    six and eight times as many traditional engineers as does the United States. 
    Other industrial countries at minimum maintain their output, while America 
    suffers an increasingly serious decline in the number of engineering graduates 
    and a lack of well-educated engineers.
"""
)
# %%
