require(tidyverse)

data = read_csv("Mapping_landscape_ABM/Data/data.csv")

# in one abstract, a greater-than-equal sign is misrepresented by a copyright sign, fix this manually:
data <- data %>%
  mutate(Abstract = str_replace(Abstract, "31 patients aged ©60 years", "31 patients aged ⩾60 years"))


# define copyright statements and similar with regular expressions
regex_copyright_start <- "^Vancraeyenest[:print:]*2020 Elsevier Inc.;|^Monitoring outcome[:print:]*2020 Elsevier Inc.;|^Although neuronal oscillations[:print:]*2020 Elsevier Inc.;|^Kaufman et al. imaged[:print:]*2020 Elsevier Inc.;|^The mesolimbic dopamine system[:print:]*2018 Elsevier Inc.;"
regex_psycinfo <- "\\(?(PsycInfo|PsycINFO)[:print:]*$" # matches end of strings that start with PsycInfo/PsycINFO, optionally preceded by "("
regex_copyright <- "((Copyright\\s*)|©)\\s*[:print:]*?$" # matches end of strings that start with Copyright or the Copyright symbol (non-greedy)
regex_sigstatement <- "Significance Statement[:print:]*$" # matches Significance Statement
regex_reshigh <- "Research Highlights[:print:]*$" # matches Research Highlights
regex_noteworthy <- "NEW & NOTEWORTHY [:print:]*$" # matches NEW & NOTEWORTHY sections
regex_au <- "(^AU)|(: Pleaseconfirmthatallheadinglevelsarerepresentedcorrectly)"

# combine regex in vector
regex_list <- c(regex_copyright_start, regex_psycinfo, regex_copyright, regex_sigstatement, regex_reshigh, regex_noteworthy, regex_au)

# extract regex from abstracts and write to file
# str_extract_all(data$Abstract, pattern=paste(regex_list, collapse="|")) %>% unlist() %>% write_lines("extract.txt", sep="\n\n")

# clean abstracts by removing regex matches
data <- data %>%
  mutate(Abstract_cleaned = str_remove_all(Abstract, pattern=paste(regex_list, collapse="|")))


# plot histogram of abstract length
data %>% mutate(abstract_nchar = nchar(Abstract_cleaned)) %>% pull(abstract_nchar) %>% hist()



# remove organizers

# check for word starting with a uppercase letter followed by a colon (potential organizers)
data$Abstract_cleaned %>% str_match_all("[:upper:]\\w+:") %>% unlist() %>% table() %>% sort()

# list organizers, (?i) starts case-insensitive part
organizers <- c("S(?i)ignificance",
                "R(?i)esults?",
                "M(?i)ain results?",
                "B(?i)ackgrounds?",
                "B(?i)ackground and aims?",
                "B(?i)ackground and objectives?",
                "B(?i)ackground/objective",
                "I(?i)ntroduction",
                "R(?i)ationales?",
                "P(?i)urposes?",
                "I(?i)mportance",
                "M(?i)ethods?",
                "M(?i)ethodolody",
                "A(?i)ims?",
                "F(?i)indings?",
                "D(?i)iscussion",
                "D(?i)iscussion and conclusions?",
                "D(?i)iscussion/conclusion",
                "C(?i)onclusions?",
                "O(?i)bjectives?",
                "L(?i)imitations?",
                "A(?i)bstract",
                "D(?i)esign",
                "A(?i)pplications?",
                "S(?i)ummary",
                "I(?i)nterpretation",
                "A(?i)pproach",
                "O(?i)riginality"
)

# define organizer context
context <- "(/[:graph:]+)?[:punct:]?[:blank:]*(?-i)(?=([:upper:]|[:digit:]))" # optional: slash followed by symbols. then: 0 or 1 punctuations, 0 or more blanks, followed by a digit or an uppercase letter

# bring organizers and context together
regex_organizers <- paste0(organizers, context, collapse="|")


# show organizers
str_extract_all(data$Abstract_cleaned, regex_organizers) %>% unlist() %>% table() %>% sort()

# remove organizers
data <- data %>%
  mutate(Abstract_cleaned = str_remove_all(Abstract_cleaned, pattern=regex_organizers))


write_csv(data, "Mapping_landscape_ABM/Data/data_cleaned.csv")
