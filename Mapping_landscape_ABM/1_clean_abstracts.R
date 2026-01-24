require(tidyverse)

data = read_csv("Mapping_landscape_ABM/Data/data_cleaned_filtered_3.csv")

# in one abstract, a greater-than-equal sign is misrepresented by a copyright sign, fix this manually:
before_manual <- data$Abstract_cleaned
data <- data %>%
  mutate(Abstract_cleaned = str_replace(Abstract_cleaned, "31 patients aged ©60 years", "31 patients aged ⩾60 years"))
after_manual <- data$Abstract_cleaned

cat("\n==== Manual check ====\n")
cat("Rows changed:", sum(before_manual != after_manual, na.rm = TRUE), "\n")


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

# this here is for some checks:
patterns <- regex_list
names(patterns) <- c("copyright_start","psycinfo","copyright",
                     "sigstatement","reshigh","noteworthy","au")

match_counts <- map_dfc(patterns, ~ str_count(data$Abstract_cleaned, .x))
colnames(match_counts) <- paste0("n_", names(patterns))

cat("\n=== Regex hits BEFORE removal ===\n")
print(sort(colSums(match_counts, na.rm = TRUE), decreasing = TRUE))
cat("Rows with ANY match:", sum(rowSums(match_counts, na.rm = TRUE) > 0), "\n")

before_regex <- data$Abstract_cleaned

# extract regex from abstracts and write to file
# str_extract_all(data$Abstract, pattern=paste(regex_list, collapse="|")) %>% unlist() %>% write_lines("extract.txt", sep="\n\n")

# clean abstracts by removing regex matches
data <- data %>%
  mutate(Abstract_cleaned = str_remove_all(Abstract_cleaned, pattern=paste(regex_list, collapse="|")))

#
after_regex <- data$Abstract_cleaned
removed_chars_regex <- nchar(before_regex) - nchar(after_regex)
cat("\n--- Regex removal (copyright/psycinfo/etc) ---\n")
cat("Rows changed:", sum(before_regex != after_regex, na.rm = TRUE), "\n")
cat("Total chars removed:", sum(removed_chars_regex, na.rm = TRUE), "\n")
print(summary(removed_chars_regex))

# plot histogram of abstract length
#data %>% mutate(abstract_nchar = nchar(Abstract_cleaned)) %>% pull(abstract_nchar) %>% hist()
pdf("Mapping_landscape_ABM/Outputs/hist_abstract_length.pdf", width = 8, height = 5)
data %>%
  mutate(abstract_nchar = nchar(Abstract_cleaned)) %>%
  pull(abstract_nchar) %>%
  hist(main = "Abstract length in characters", xlab = "nchar")
dev.off()

abstract_nchar <- nchar(data$Abstract_cleaned)
cat("\n=== Abstract length summary (AFTER regex removal) ====\n")
print(summary(abstract_nchar))
cat("Mean:", mean(abstract_nchar, na.rm=TRUE), "\n")
cat("Median:", median(abstract_nchar, na.rm=TRUE), "\n")
cat("SD:", sd(abstract_nchar, na.rm=TRUE), "\n")

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


# check again 
org_hits <- str_count(data$Abstract_cleaned, regex_organizers)
cat("\n==== Organizer hits BEFORE removal ====\n")
cat("Rows with >=1 organizer:", sum(org_hits > 0, na.rm=TRUE), "\n")
print(summary(org_hits))
cat("\nTop organizers:\n")
print(sort(table(unlist(str_extract_all(data$Abstract_cleaned, regex_organizers))),
           decreasing = TRUE))

####
before_org <- data$Abstract_cleaned
data <- data %>%
  mutate(Abstract_cleaned = str_remove_all(Abstract_cleaned, pattern = regex_organizers))

after_org <- data$Abstract_cleaned
removed_chars_org <- nchar(before_org) - nchar(after_org)
cat("\n=== Organizer removal ===\n")
cat("Rows changed:", sum(before_org != after_org, na.rm=TRUE), "\n")
cat("Total chars removed:", sum(removed_chars_org, na.rm=TRUE), "\n")
print(summary(removed_chars_org))

####
cat("\n=== Sanity checks ==\n")
cat("Empty abstracts after cleaning:",
    sum(is.na(data$Abstract_cleaned) | str_trim(data$Abstract_cleaned) == ""), "\n")
cat("Still contains © :",
    sum(str_detect(data$Abstract_cleaned, "©"), na.rm=TRUE), "\n")
cat("Still has 'UppercaseWord:' pattern:",
    sum(str_detect(data$Abstract_cleaned, "[:upper:]\\w+:"), na.rm=TRUE), "\n")


# show organizers
str_extract_all(data$Abstract_cleaned, regex_organizers) %>% unlist() %>% table() %>% sort()

# remove organizers
data <- data %>%
  mutate(Abstract_cleaned = str_remove_all(Abstract_cleaned, pattern=regex_organizers))


write_csv(data, "Mapping_landscape_ABM/Data/data_cleaned_3_tryout.csv")
