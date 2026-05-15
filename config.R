# config.R
# Project-wide settings — source this at the top of every R script:
#   source(here::here("config.R"))
#
# Output format toggles
RENDER_HTML <- FALSE  # set TRUE to also render .html alongside .md
RENDER_PDF  <- FALSE  # set TRUE to also render .pdf (requires Chrome on PATH)

# ---------------------------------------------------------------------------
# prune_dated(dir, pattern, keep = 2)
#
# After writing a dated output file, call this to cap the number of versions.
# Keeps the `keep` most-recent date groups and deletes everything older.
# Works on files AND companion _files/ directories (e.g. Quarto HTML libs).
#
# Args:
#   dir     – directory to scan (use here::here(...))
#   pattern – regex matching the filename prefix + date pattern, e.g.
#             "^DSS_ingest_[0-9]{4}-[0-9]{2}-[0-9]{2}"
#   keep    – number of dated versions to retain (default 2)
# ---------------------------------------------------------------------------
prune_dated <- function(dir, pattern, keep = 2L) {
  files   <- list.files(dir, pattern = pattern, full.names = TRUE)
  subdirs <- list.dirs(dir, recursive = FALSE, full.names = TRUE)
  subdirs <- subdirs[grepl(pattern, basename(subdirs), perl = TRUE)]
  entries <- unique(c(files, subdirs))
  if (!length(entries)) return(invisible(NULL))

  # Extract YYYY-MM-DD from each entry name; drop entries with no date
  m     <- regexpr("[0-9]{4}-[0-9]{2}-[0-9]{2}", basename(entries))
  dates <- ifelse(m > 0L, regmatches(basename(entries), m), NA_character_)
  entries <- entries[!is.na(dates)]
  dates   <- dates[!is.na(dates)]
  if (!length(entries)) return(invisible(NULL))

  u_dates <- sort(unique(dates), decreasing = TRUE)
  if (length(u_dates) <= keep) return(invisible(NULL))

  for (d in u_dates[seq.int(keep + 1L, length(u_dates))]) {
    for (f in entries[dates == d]) {
      message("  Pruned: ", basename(f))
      unlink(f, recursive = TRUE)
    }
  }
  invisible(NULL)
}
