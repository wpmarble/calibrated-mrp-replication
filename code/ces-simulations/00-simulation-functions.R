## Simulation Functions

# Function for sampling --------------------------------------------------

# generate a sample with differential nonresponse
# p(sample) \propto inv.logit(dnr_outcomes %*% dnr_beta)
generate_sample <- function(
  population,
  n,
  dnr_outcomes = NULL,
  dnr_beta = NULL
) {
  if (!is.null(dnr_outcomes)) {
    y <- as.matrix(population[, dnr_outcomes])
    y[y==0] <- -1 # turn into matrix of {-1, 1}
    probs <- y %*% dnr_beta
    probs <- plogis(probs)
  } else {
    probs <- rep(1, nrow(population))
  }
  samp <- sample(1:nrow(population), size = n, replace = TRUE, prob = probs)

  population[samp, ]
}




# texreg helper
format_texreg_N_rows <- function(texreg_output) {
  # this function is helpful for fixing the output of texreg. I like to use
  # dcolumns to align decimal points in coefficients, but it does not work well
  # for sample sizes because it places the number all the way to the left. 
  # This function detects rows starting with $N$ and wraps entries in that row
  # with \multicolumn{1{c}{ [content] }. It also ensures numbers > 1k have commas.
  # Split into lines for row-wise manipulation
  lines <- strsplit(texreg_output, "\n")[[1]]
  
  # Process each line
  lines <- lapply(lines, function(line) {
    # Match any line that starts with a $N$-type label
    if (str_detect(line, "^\\$N\\$")) {
      # Split by '&' separator
      parts <- str_split(line, "\\s*&\\s*")[[1]]
      
      # Keep the first cell as-is
      lhs <- parts[1]
      
      # Format each numeric RHS cell
      rhs <- parts[-1]
      rhs_formatted <- rhs %>% 
        str_replace_all("[^0-9]", "") %>%                # Strip any non-digit characters
        as.numeric() %>%                                 # Convert to numbers
        format(big.mark = ",", scientific = FALSE) %>%   # Format with commas
        {paste0("\\multicolumn{1}{c}{$", ., "$}")}         # Wrap in multicolumn
      
      # Reassemble the line
      line <- paste0(paste(c(lhs, rhs_formatted), collapse = " & "), "  \\\\")
    }
    line
  })
  
  # Recombine lines into a single LaTeX string
  paste(unlist(lines), collapse = "\n")
}
