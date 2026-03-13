## Download CES (Cooperative Election Study) data from Harvard Dataverse
##
## This script downloads the CES data files needed for the simulation study
## (Appendix I). Files are saved to data/ces/ and are not redistributed
## with the replication package due to their size.
##
## Requires: dataverse R package
## Usage: Rscript code/download-ces-data.R

library(dataverse)

out_dir <- "data/ces"
dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

# CES datasets and their Dataverse DOIs
datasets <- list(
  list(
    doi = "doi:10.7910/DVN/II2DB6",
    file = "cumulative_2006-2024.feather",
    subdir = "cces-cumulative",
    desc = "CES Cumulative File (2006-2024)"
  ),
  list(
    doi = "doi:10.7910/DVN/OSXDQO",
    file = "cumulative_ces_policy_preferences.dta",
    subdir = "cces-policy",
    desc = "CES Cumulative Policy Preferences"
  ),
  list(
    doi = "doi:10.7910/DVN/PR4L8P",
    file = "CCES22_Common_OUTPUT_vv_topost.dta",
    subdir = "cces-2022",
    desc = "CES 2022 Common Content"
  ),
  list(
    doi = "doi:10.7910/DVN/JQJTCC",
    file = "CCES23_Common_OUTPUT.dta",
    subdir = "cces-2023",
    desc = "CES 2023 Common Content"
  )
)

for (ds in datasets) {
  dest_dir <- file.path(out_dir, ds$subdir)
  dest_file <- file.path(dest_dir, ds$file)

  if (file.exists(dest_file) && file.size(dest_file) > 0) {
    message("Already exists: ", dest_file)
    next
  }

  dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  message("Downloading: ", ds$desc, " ...")

  tryCatch({
    # List files in the dataset to find the right one
    ds_files <- dataset_files(ds$doi, server = "dataverse.harvard.edu")

    # Find the target file. Dataverse ingests .dta files and relabels them
    # as .tab, so also search for the .tab version of the filename.
    search_names <- unique(c(ds$file, sub("\\.dta$", ".tab", ds$file)))
    target <- NULL
    for (f in ds_files) {
      if (f$label %in% search_names) {
        target <- f
        break
      }
    }

    if (is.null(target)) {
      warning("Could not find file '", ds$file, "' in dataset ", ds$doi,
              ". Available files: ",
              paste(sapply(ds_files, function(x) x$label), collapse = ", "))
      next
    }

    # Download in original format (e.g. .dta rather than ingested .tab)
    raw <- get_file_by_id(target$dataFile$id, server = "dataverse.harvard.edu",
                          format = "original")
    writeBin(raw, dest_file)
    message("  Saved: ", dest_file, " (",
            round(file.size(dest_file) / 1e6, 1), " MB)")

  }, error = function(e) {
    warning("Failed to download ", ds$desc, ": ", e$message)
  })
}

message("\nDone. Downloaded files:")
for (ds in datasets) {
  f <- file.path(out_dir, ds$subdir, ds$file)
  if (file.exists(f)) {
    message("  ", f, " (", round(file.size(f) / 1e6, 1), " MB)")
  } else {
    message("  ", f, " -- MISSING")
  }
}
