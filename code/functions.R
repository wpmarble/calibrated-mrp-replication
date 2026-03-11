## Functions used to generate weights


# z_score2 ----------------------------------------------------------------

# function to get z score divided by 2 (make sd = .5)
z_score2 = function(x, na.rm=TRUE){
  (x - mean(x, na.rm=na.rm)) / (2*sd(x, na.rm=na.rm))
}



# marg --------------------------------------------------------------------

# get margin on vote
marg = function(x){
  x - (1-x)
}

# prettyNum2 --------------------------------------------------------------


prettyNum2 = function(...) {
  prettyNum(..., big.mark=",")
}



# rakeWeights -------------------------------------------------------------


# svy_data: cleaned SM data
# population_data: population margins, in the form of a data frame with columns
#                 "variable", "level" (of the variable), and "prop" (proportion)
# variables: character vector of weighting variables
# trim: trim weights to [lower, upper]?
# add: return svy_data with weights added? otherwise return weight vector
# wtname: if add = TRUE, what to name weight var 
# ...: additional args passed to survey::rake()


rakeWeights = function(
    svy_data,           
    population_data,    
    variables,        
    initwts = NULL,
    trim = FALSE, upper = 7, lower = .4, 
    strict = TRUE,
    add = FALSE,        
    wtname = "weight",  
    control = list(epsilon = 1e-10, maxit = 5e4),
    ...                 
) {
  require(survey)
  
  # make sure variables match
  if (!all(variables %in% names(svy_data))){
    stop("all variables must be in svy_data")
  }
  if (!all(variables %in% population_data$variable)){
    stop("all variables must be in population_data")
  }
  
  
  orig_data = svy_data
  
  # We can't have missing values in the weighting variables
  tokeep = svy_data %>% 
    select(!!variables) 
  tokeep = !apply(tokeep, 1, anyNA)
  svy_data = svy_data[tokeep,]
  included = which(tokeep)
  omitted = which(!tokeep)
  message("dropped ", prettyNum(sum(!tokeep), big.mark=","), " cases (", 
          round(mean(!tokeep)*100, 1), "%) due to missing weighting variables")
  
  # Put survey data into svydesign object
  svy = svydesign(ids = ~1, data = svy_data, weights = initwts)
  
  # Prepare demographic variables
  targets = population_data %>% 
    rename(Freq = prop) %>% 
    group_by(variable) %>% 
    group_split()
  names(targets) = unlist(lapply(targets, function(x) tolower(x$variable[1])))
  targets = targets[variables]
  targets = lapply(targets, function(x){
    vname = tolower(x$variable[1])
    # wtf dplyr what is !! :=
    x %>% rename(!!vname := level) %>% select(!!vname, Freq)
  })
  
  
  # Make sure levels all match
  for (v in variables){
    svy_levels = unique(svy_data[[v]])
    pop_levels = unique(population_data$level[population_data$variable == v])
    if(!setequal(svy_levels, pop_levels)){
      stop("differing levels for variable ", v)
    }
  }
  
  # generate weights using survey::rake()
  forms = as.list(paste("~", variables))
  forms = lapply(forms, formula)
  wts = rake(svy, 
             sample.margins = forms,
             population.margins = targets,
             control = control,
             ...)
  
  
  if (trim){
    # need to translate upper/lower because the weights currently don't avg 1
    tmp = weights(wts)
    mtmp = mean(tmp)
    upper = upper * mtmp
    lower = lower * mtmp
    wts = trimWeights(wts, upper = upper, lower = lower, strict = strict)
  }
  
  # return survey weights normalized to have a mean of 1. 
  # For rows that had NAs in the  weighting variables, there will also be 
  # NAs for the weights.
  wtsout = weights(wts)
  wtsout = wtsout / mean(wtsout)
  out    = data.frame(id = included, weight = wtsout)
  if (length(omitted) > 0){
    out    = rbind(out,
                   data.frame(id = omitted, weight = NA))
  }
  out    = out %>% arrange(id)
  
  
  if (add){
    orig_data[[wtname]] = out$weight
    return(orig_data)
  } else {
    return(out$weight)
  }
  
  
  
}




# SE of mean with design effect adjustment --------------------------------
# d.eff = 1 + cv^2(wts) 
#       = 1 + [sd(wts) / mean(wts)]^2
# wtd.se = d * SE(mean(x))
SEMdeff = function(x, w){
  if (!(length(x) == length(w))){
    stop("x and w different lengths")
  }
  n = length(na.omit(x))
  
  sd.x = sqrt(Hmisc::wtd.var(x, w, na.rm = TRUE))
  cv = sd(w, na.rm = TRUE) / mean(w, na.rm = TRUE)
  deff = 1 + cv^2
  se = deff * sd.x / sqrt(n)
  return(se)
}




