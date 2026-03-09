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


# forceVote ---------------------------------------------------------------


#' forceToVote: perform a single raking step to match a vote margin
#' svy_data: a data.frame of survey results
#' vote_data: a data.frame with election results. variables should include
#'            vote_var as a column along with Pop.Freq. 
#' vote_var: the variable storing vote choice in svy_data and vote_data. 
#'           levels much match between svy_data and vote_data
#' initwt: initial weights used to compute sample margin
#' 
#' 
#' 
#' 
#svy_data = ga
#vote_data = ga.vote                 
#vote_var="senate.topline"
#initwt = "weight"
forceToVote = function(svy_data, vote_data, vote_var, initwt = NULL){
  
  if (!(vote_var %in% names(svy_data) & vote_var %in% names(vote_data))){
    stop("vote_var must be present in both svy_data and vote_data")
  }
  
  # Compute sample margin
  if (!is.null(initwt)){
    wt = svy_data[[initwt]]
  } else {
    wt = rep(1, nrow(svy_data))
  }
  marg = data.frame(prop.table(wtd.table(svy_data[[vote_var]], w = wt)))
  # if (nrow(marg) == 0){
  #   cat(sprintf("skipping %s\n", s))
  #   next
  # }
  names(marg) = c(vote_var, "Samp.Freq")
  
  # Compute adjustment ratio
  vote_data = left_join(marg, vote_data)
  vote_data$adj_fact = vote_data$Pop.Freq / vote_data$Samp.Freq
  
  # Update weight
  out = left_join(svy_data, 
                  vote_data %>% select(state, house.vote, adj_fact)) %>% 
    mutate(final_wt_forced = final_wt * adj_fact) %>% 
    # select(-adj_fact)
    pluck("final_wt_forced")
  
  return(out)
}




# compareDistrib ----------------------------------------------------------


## Function to Compare Raw Data and Weighting Targets
compareDistrib = function(
    svy_data,  
    population_data,
    wt = NULL,   # should be vector
    variables
){
  
  
  require(questionr)
  out = population_data %>% 
    rename(population_prop = prop) %>% 
    select(variable, level, population_prop)
  outlist = list()
  for (v in variables){
    
    # get sample proportions, excluding NA's, with and without weights
    vout = data.frame( prop.table(table(svy_data[[v]], useNA = "no")))
    
    # get wtd estimates
    if (!is.null(wt)){
      vout_wt   = data.frame( prop.table(wtd.table(svy_data[[v]], w = wt, useNA = "no")))
      
      vout = left_join(
        vout %>% 
          rename(  sample_prop_unwtd = Freq),
        vout_wt %>% 
          rename(  sample_prop_wtd = Freq),
        by = "Var1")
      vout = vout %>% 
        rename(level = Var1)
    }  else {
      vout = vout %>% 
        rename(level = Var1,
               sample_prop_unwtd = Freq)
    }
    vout = vout %>% 
      mutate(variable = v) 
    
    
    
    
    # get N for each cell in survey
    ns = svy_data %>% 
      group_by(!!!syms(v)) %>% 
      summarise(sample_n = n()) %>% 
      rename(level := !!v)
    
    vout = left_join(
      vout, 
      ns, 
      by = "level"
    )
    
    # for weights, calculate sd(wt) / mean(wt) of weights within cell
    # (the "coefficient of variation")
    if (!is.null(wt)){
      wt_cv = aggregate(wt, list(svy_data[[v]]), function(x) sd(x, na.rm=TRUE) / mean(x, na.rm=TRUE))
      wt_cv = wt_cv %>% 
        rename(level = Group.1, wt_cv = x)
      vout = left_join(
        vout, 
        wt_cv, 
        by = "level"
      )
    }
    
    # join with population data
    thisout = full_join(
      out %>% 
        filter(variable == v),
      vout, 
      by = c("variable", "level")
    )
    thisout = thisout %>% 
      relocate(variable, level, population_prop, sample_n, starts_with("wt_"),
               ends_with("_unwtd"), ends_with("_wtd")) 
    
    thisout = thisout %>% 
      mutate(diff_unwtd = population_prop - sample_prop_unwtd,
             rel_diff_unwtd = diff_unwtd / population_prop)
    
    if (!is.null(wt)){
      thisout = thisout %>% 
        mutate(diff_wtd = population_prop - sample_prop_wtd,
               rel_diff_wtd = diff_wtd / population_prop)
    }
    
    outlist[[v]] = thisout
  }
  return(bind_rows(outlist))
}




# wtdTables ---------------------------------------------------------------


# function to compute weighted tables across groups of weighting variables
wtdTables = function(
    svy_data, 
    variable,
    wts,     # char vector giving names of wt variables in svy_data
    useNA = "no", # passed to table() and wtd.table()
    report_unwtd = TRUE
) {
  require(questionr)
  stopifnot(all(wts %in% names(svy_data)))
  
  out = list()
  if (report_unwtd){
    unwtd = data.frame(prop.table(table(svy_data[[variable]], useNA = useNA)))
    unwtd = unwtd %>% 
      rename(level = Var1,
             est = Freq) %>% 
      mutate(type = "Unweighted")
    out[["unwtd"]] = unwtd
  }
  for (w in wts){
    tab = data.frame(prop.table(wtd.table(svy_data[[variable]], 
                                          w = svy_data[[w]],
                                          useNA = useNA)))
    tab = tab %>% 
      rename(level = Var1,
             est = Freq) %>% 
      mutate(type = w)
    out[[w]] = tab
  }
  
  out = bind_rows(out)
  return(out)
  
  
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

designEffect = function(w){
  cv = sd(w, na.rm = TRUE) / mean(w, na.rm = TRUE)
  1 + cv^2
}




# bootstrapGLMER ----------------------------------------------------------



# bootstrap a binary glmer model that is estimated using a collapsed dataset.
# optionally make the random sample smaller than the actual dataset by setting
# sample_size argument. 

# By default, returns a list of bootstrapped model replicates (i.e. list of
# glmer fits)
# If f is supplied, the re-fit model is passed to .f. Additional arguments to
# .f given by ...
bootstrapGLMER = function(
    model,
    sample_size = "all",
    nboot = 10, 
    control,
    f = NULL,
    ... # args passed to .f
) {
  
  
  # extract data used to estimate model
  dat = as_tibble(model@frame)
  nm = trimws(gsub("cbind|\\(|\\)", "", strsplit(names(dat)[1], ",")[[1]]))
  dat$successes = dat[,1][[1]][,1]
  dat$failures  = dat[,1][[1]][,2]
  dat[,1] = NULL
  
  # extract formula
  formula = formula(model)
  
  # recreate an individual-level df from the number of successes and failures
  successes = dat %>% 
    uncount(successes) %>% 
    select(-failures) %>% 
    mutate(y = 1)
  
  failures = dat %>% 
    uncount(failures) %>% 
    select(-successes) %>% 
    mutate(y = 0)
  
  ind_df = bind_rows(successes, failures)
  
  # generate bootstrap samples. this will have a list of indices.
  idx = 1:nrow(ind_df)
  boot = replicate(
    nboot, 
    sample(idx, 
           ifelse(sample_size == "all", 
                  length(idx), 
                  sample_size), 
           replace = TRUE), 
    simplify = FALSE)
  
  
  # refit models
  res = map(
    boot, 
    function(x){
      
      # re-collapse data to be successes and failures 
      newdat = ind_df[unlist(x),] %>% 
        group_by(across(-y)) %>% 
        summarise(y1 = sum(y),
                  y2 = sum(1 - y)) 
      names(newdat)[names(newdat) %in% c("y1", "y2")] = nm
      
      # re-fit model
      new_fit = glmer(formula,
                      data = newdat,
                      family = "binomial",
                      control = control)
      
      if (!is.null(f)){
        out = f(new_fit, ...)
      } else {
        out = new_fit
      }
      return(out)
    })
  
  return(res)
}




# poststratifyGLMER -------------------------------------------------------

# function to poststratify using a GLMER object. 

# give it a fitted model and poststratification table along
# with the names of the geography variable and the cell weight. 
# Optionally return the number of observations in the model for each geographic
# unit.
poststratifyGLMER = function(
    model, 
    poststrat,
    geography,
    cell_wt,
    report_n = TRUE
){
  
  # predict outcome in poststratification table
  pred = predict(
    model, 
    newdata = poststrat, 
    type = "response", 
    allow.new.levels = TRUE
  )
  poststrat = poststrat %>% 
    mutate(pred = pred)
  
  # get geography-level summary
  out = poststrat %>% 
    group_by(across(all_of(geography))) %>% 
    summarise(pred = weighted.mean(pred, get(cell_wt)))
  
  
  # report sample size per geographic unit, assuming geographic unit is included
  # in model frame
  if (report_n){
    d = as_tibble(model@frame)
      
      if ((geography %in% colnames(d))) {
        
        # Case 1: model is expressed as cbind(success, failure) ~ x
        # Case 2: model is expressed as y ~ x
        if ("matrix" %in% class(d[[1]])){
          d$samp_size = apply(d[[1]], 1, sum)
          ss = d %>% 
            group_by(across(all_of(geography))) %>% 
            summarise(N_est = sum(samp_size))
        } else {
          ss = d %>% 
            group_by(across(all_of(geography))) %>% 
            summarise(N_est = n())
        }
      
      out = left_join(out, ss, by = "state") %>% 
        mutate(N_est = ifelse(is.na(N_est), 0, N_est))
    }
  }
  return(out)
  
}
