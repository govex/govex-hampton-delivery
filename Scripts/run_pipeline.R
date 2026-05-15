# run_pipeline.R
# Top-level orchestrator for the Hampton Childcare Provider Pipeline.
#
# Usage (from project root):
#   Rscript Scripts/run_pipeline.R
#   # or open in RStudio / Positron and source it
#
# Seed logic:
#   If Data/seed/ contains both a CCAV and DSS ingest CSV, they are copied to
#   Data/01_ingest/ and the ingest rendering stage is skipped. This allows the
#   pipeline to run immediately from the committed seed files without
#   re-collecting data from source systems.
#
#   To collect fresh data instead:
#     1. Remove or empty Data/seed/
#     2. For DSS: the pipeline will render dss_ingest.qmd automatically
#     3. For CCAV: manually run ccav_ingest.js in Chrome DevTools, move the
#        downloaded CSV to Data/01_ingest/, then re-run this script
#
# Prerequisites:
#   R >= 4.3, Quarto >= 1.4, and all packages listed in README.md

here::i_am("Scripts/run_pipeline.R")
library(here)

# ── Locate quarto binary ──────────────────────────────────────────────────────
# Check PATH first, then common bundled locations (RStudio on macOS/Windows)
quarto_candidates <- c(
  Sys.getenv("QUARTO"),
  Sys.which("quarto"),
  "/Applications/RStudio.app/Contents/Resources/app/quarto/bin/quarto",
  "/Applications/quarto/bin/quarto",
  "/usr/local/bin/quarto"
)
quarto_bin <- quarto_candidates[nzchar(quarto_candidates) & file.exists(quarto_candidates)][1]
if (is.na(quarto_bin) || !nzchar(quarto_bin)) {
  stop(
    "quarto not found. Install from https://quarto.org, ",
    "or set the QUARTO environment variable to the quarto binary path."
  )
}

# ── Helper: render one .qmd to a Reports/ subdirectory ───────────────────────
render_module <- function(qmd_rel_path, report_subdir) {
  qmd_path   <- here(qmd_rel_path)
  output_dir <- here("Reports", report_subdir)

  dir.create(output_dir, showWarnings = FALSE, recursive = TRUE)

  cat(sprintf("\n── %s\n", qmd_rel_path))
  result <- system2(
    quarto_bin,
    args   = c("render", shQuote(qmd_path), "--output-dir", shQuote(output_dir)),
    stdout = FALSE,
    stderr = FALSE
  )
  if (result != 0) {
    stop(sprintf("quarto render failed for %s (exit code %d)", qmd_rel_path, result))
  }
  cat(sprintf("✓  %s → Reports/%s/\n", basename(qmd_path), report_subdir))
}

# ── Banner ────────────────────────────────────────────────────────────────────
cat(strrep("═", 60), "\n")
cat(sprintf("  Hampton Childcare Pipeline — %s\n", format(Sys.time(), "%Y-%m-%d %H:%M")))
cat(sprintf("  Project root: %s\n", here()))
cat(strrep("═", 60), "\n")

# ── Stage 0: Seed check ───────────────────────────────────────────────────────
seed_ccav <- list.files(here("Data", "seed"), pattern = "^CCAV_ingest_.*\\.csv$",
                        full.names = TRUE)
seed_dss  <- list.files(here("Data", "seed"), pattern = "^DSS_ingest_.*\\.csv$",
                        full.names = TRUE)
use_seed  <- length(seed_ccav) > 0 && length(seed_dss) > 0

if (use_seed) {
  cat("\nSeed files found — copying to Data/01_ingest/.\n")
  dir.create(here("Data", "01_ingest"), showWarnings = FALSE, recursive = TRUE)

  # Use the most recent seed file for each source (in case multiple exist)
  seed_ccav_use <- tail(sort(seed_ccav), 1)
  seed_dss_use  <- tail(sort(seed_dss),  1)
  dest_ccav     <- here("Data", "01_ingest", basename(seed_ccav_use))
  dest_dss      <- here("Data", "01_ingest", basename(seed_dss_use))

  if (!file.exists(dest_ccav)) {
    file.copy(seed_ccav_use, dest_ccav)
    cat(sprintf("  Copied: %s\n", basename(seed_ccav_use)))
  } else {
    cat(sprintf("  Already present: %s\n", basename(seed_ccav_use)))
  }
  if (!file.exists(dest_dss)) {
    file.copy(seed_dss_use, dest_dss)
    cat(sprintf("  Copied: %s\n", basename(seed_dss_use)))
  } else {
    cat(sprintf("  Already present: %s\n", basename(seed_dss_use)))
  }
} else {
  # No seed — check that CCAV file was manually placed before proceeding
  ccav_in_ingest <- list.files(
    here("Data", "01_ingest"), pattern = "^CCAV_ingest_.*\\.csv$"
  )
  if (length(ccav_in_ingest) == 0) {
    stop(
      "\nNo CCAV ingest file found in Data/01_ingest/.\n",
      "To collect fresh CCAV data:\n",
      "  1. Open https://stage.worklifesystems.com/parent/25 in Chrome\n",
      "  2. Click Guest Account and complete the reCAPTCHA\n",
      "  3. Open Chrome DevTools (Cmd+Option+J / Ctrl+Shift+J)\n",
      "  4. Paste the contents of Scripts/01_ingest/ccav_ingest.js and press Enter\n",
      "  5. Move the downloaded CSV to Data/01_ingest/\n",
      "  6. Re-run this script\n"
    )
  }
}

# ── Stage 1: Ingest reports ───────────────────────────────────────────────────
# dss_ingest.qmd scrapes DSS if no file exists in Data/01_ingest/; otherwise
# renders a report from the existing file (e.g. copied from seed).
render_module("Scripts/01_ingest/dss_ingest.qmd",         "01_ingest")
render_module("Scripts/01_ingest/ccav_ingest_report.qmd", "01_ingest")

# ── Stage 2: Standardize ──────────────────────────────────────────────────────
render_module("Scripts/02_standardize/ccav_standardize.qmd",  "02_standardize")
render_module("Scripts/02_standardize/dss_standardize.qmd",   "02_standardize")
render_module("Scripts/02_standardize/hours_standardize.qmd", "02_standardize")

# ── Stage 3: Merge ────────────────────────────────────────────────────────────
render_module("Scripts/03_merge/manual_override.qmd",  "03_merge")
render_module("Scripts/03_merge/merge_providers.qmd",  "03_merge")

# ── Stage 4: Analyze ──────────────────────────────────────────────────────────
render_module("Scripts/04_analyze/providers_analysis.qmd", "04_analyze")

# ── Stage 5: Visualize ────────────────────────────────────────────────────────
render_module("Scripts/05_visualize/visualizations.qmd", "05_visualize")

# ── Done ──────────────────────────────────────────────────────────────────────
cat("\n", strrep("═", 60), "\n", sep = "")
cat(sprintf("  Done. Reports → Reports/   Plots → Plots/\n"))
cat(strrep("═", 60), "\n")
