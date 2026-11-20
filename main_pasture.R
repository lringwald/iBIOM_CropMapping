##### MAIN PASTURE & RUMINANT LIVESTOCK PIPELINE
#####
##### P02       prepare EPIC grassland, FAOSTAT accounting (QCL/GLE/EMN/EK), and Eurostat NUTS2 priors
##### P03       load shared grids, accounts, priors, and sourced reference constants
##### P04-P12   per country x year: LUM startmap, EPIC forage, gamma_c, 2D IPF livestock, milk/meat, GHG, exports
##### P13-P16   run-scoped summary, plots, SimU aggregation, report & manifest

rm(list = ls())
gc()

run_start_utc <- format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")

if (!file.exists("user_config.R")) stop("user_config.R not found.")
source("user_config.R")
source("codes/01_settings.R")
source("codes/support/fun_pasture_contracts.R")

cascade_engine_info <- ensure_cascade_engine()

library(dplyr)
library(tidyr)
library(sf)
library(readr)
library(terra)
library(countrycode)
library(data.table)
library(stringr)

## Validate required config options upfront (no hidden defaults across scripts)
req_cfg <- c("INPUT_DIR", "PASTURE_RESULT_TAG", "PASTURE_RUN_YEARS", "lum_grass_map",
             "LIVESTOCK_ACCOUNTING_SOURCE", "FAOSTAT_EMISSION_SOURCE",
             "USE_EUROSTAT_PRIORS", "GWP_VERSION", "EXPORT_PASTURE_SPATIAL")
miss_cfg <- req_cfg[!vapply(req_cfg, exists, logical(1))]
if (length(miss_cfg) > 0L) stop("Missing required config options in user_config.R: ", paste(miss_cfg, collapse = ", "))

## Run-scoped directory initialization
out_root <- file.path("output", PASTURE_RESULT_TAG)
for (sub in c("", "aggregated", "simu_res", "country_res", "plot", "report")) {
  dir.create(file.path(out_root, sub), recursive = TRUE, showWarnings = FALSE)
}

manifest_ledger    <- list()
manifest_fallbacks <- list()

## Stage P02 & P03
source("./codes/pasture/P02_prepare_pasture_inputs.R")
source("./codes/pasture/P03_load_shared_pasture.R")

country_steps <- c(
  "P04_initialize_country.R",
  "P05_prepare_pasture_startmap.R",
  "P07_load_EPIC_grass.R",
  "P09_livestock_disaggregation.R",
  "P10_milk_meat_production.R",
  "P11_emissions_accounting.R"
)

if (!exists("SKIP_EXISTING")) SKIP_EXISTING <- FALSE

for (JOB in seq_len(nrow(country_grid))) {
  gc()
  job.reg  <- as.character(country_grid$lama.regs[JOB])
  job.year <- as.character(country_grid$years[JOB])
  res.file  <- pasture_country_rds_path(PASTURE_RESULT_TAG, job.reg, job.year)
  fail.file <- pasture_country_fail_path(PASTURE_RESULT_TAG, job.reg, job.year)

  if (isTRUE(SKIP_EXISTING) && file.exists(res.file)) {
    message(sprintf("↷ SKIPPING JOB: %d / %d (%s, %s) — result exists",
                    JOB, nrow(country_grid), job.reg, job.year))
    next
  }

  message(sprintf("\n=== [%d/%d] %s (%s) ===", JOB, nrow(country_grid), job.reg, job.year))
  tryCatch({
    for (step in country_steps) {
      source(file.path("./codes/pasture", step), local = TRUE)
    }
    source("./codes/pasture/P12_country_outputs.R", local = TRUE)
    if (file.exists(fail.file)) file.remove(fail.file)
    message(sprintf("✔ COMPLETED %s (%s)", job.reg, job.year))
  }, error = function(e) {
    message(sprintf("✘ FAILED %s (%s): %s", job.reg, job.year, conditionMessage(e)))
    save_rds_atomic(list(region = job.reg, year = job.year, error = conditionMessage(e)), fail.file)
  })
}

failed_files <- list.files(out_root, pattern = "^FAILED_", full.names = TRUE)
if (length(failed_files) > 0L) {
  stop(sprintf("Pipeline stopped: %d country job(s) failed: %s",
               length(failed_files), paste(basename(failed_files), collapse = ", ")))
}

## Stage P13 - P15 + Independent Performance Checks (P13b) + Plots (P14)
source("./codes/pasture/P13_summarise.R")
source("./codes/pasture/P15_aggregate_SimU_LU.R")
source("./codes/pasture/P13b_performance_checks.R")
source("./codes/pasture/P14_plot_results.R")

## Write run manifest before P16 report generation
git_cmd <- function(...) tryCatch(system2("git", c(...), stdout = TRUE, stderr = FALSE), error = function(e) NA_character_)
lum_files_resolved <- setNames(
  vapply(as.character(PASTURE_RUN_YEARS), function(y) resolve_lum_raster(y, lum_dir = LUM.path, input_dir = INPUT_DIR, must_exist = FALSE), character(1)),
  as.character(PASTURE_RUN_YEARS)
)
manifest <- list(
  run_id              = PASTURE_RESULT_TAG,
  start_utc           = run_start_utc,
  end_utc             = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  git_commit          = git_cmd("rev-parse", "HEAD")[1],
  git_branch          = git_cmd("rev-parse", "--abbrev-ref", "HEAD")[1],
  git_dirty           = length(git_cmd("status", "--porcelain", "--untracked-files=no")) > 0L,
  machine             = Sys.info()[["nodename"]],
  r_version           = R.version.string,
  engine_cascade_core = cascade_engine_info,
  lum_files           = as.list(lum_files_resolved),
  config      = list(
    INPUT_DIR                   = INPUT_DIR,
    LUM_DIR                     = LUM.path,
    SHARED_INPUT_DIR            = SHARED_INPUT_DIR,
    PASTURE_RESULT_TAG          = PASTURE_RESULT_TAG,
    PASTURE_RUN_YEARS           = PASTURE_RUN_YEARS,
    PASTURE_COUNTRIES           = PASTURE_COUNTRIES,
    lum_grass_map               = lum_grass_map,
    LIVESTOCK_ACCOUNTING_SOURCE = LIVESTOCK_ACCOUNTING_SOURCE,
    FAOSTAT_EMISSION_SOURCE     = FAOSTAT_EMISSION_SOURCE,
    USE_EUROSTAT_PRIORS         = USE_EUROSTAT_PRIORS,
    GWP_VERSION                 = GWP_VERSION,
    EXPORT_PASTURE_SPATIAL      = EXPORT_PASTURE_SPATIAL
  ),
  input_md5   = unname(tools::md5sum(c(EPIC.grass.pq.path, EPIC.grass.ref.pq.path, faostat.accounts.pq.path, eurostat.priors.lsk.pq.path, eurostat.priors.milk.pq.path, eurostat.priors.mfa.pq.path, grid.1km.map.path, pasture.params.csv, lum.grass.class.csv, band.catalogue.csv))),
  input_files = c(EPIC.grass.pq.path, EPIC.grass.ref.pq.path, faostat.accounts.pq.path, eurostat.priors.lsk.pq.path, eurostat.priors.milk.pq.path, eurostat.priors.mfa.pq.path, grid.1km.map.path, pasture.params.csv, lum.grass.class.csv, band.catalogue.csv)
)
save_rds_atomic(manifest, file.path(out_root, "run_manifest.rds"))
if (requireNamespace("jsonlite", quietly = TRUE)) {
  write_lines_atomic(jsonlite::toJSON(manifest, auto_unbox = TRUE, pretty = TRUE), file.path(out_root, "run_manifest.json"))
}

## Stage P16
source("./codes/pasture/P16_run_report.R")
message("\n✔ Pasture & Livestock pipeline finished cleanly.")

