##### PASTURE P13: resolve country outputs from explicit country_grid manifest (no globs),
##### assert run_id & key uniqueness, reconcile conservation ledger, and save aggregated bundle.

library(data.table)
library(dplyr)

expected_files <- vapply(
  seq_len(nrow(country_grid)),
  function(i) pasture_country_rds_path(PASTURE_RESULT_TAG, country_grid$lama.regs[i], country_grid$years[i]),
  character(1)
)
missing_files <- expected_files[!file.exists(expected_files)]
if (length(missing_files) > 0L) {
  stop(sprintf("[P13] Missing %d expected country output file(s): %s",
               length(missing_files), paste(missing_files, collapse = ", ")))
}

cell_list     <- vector("list", length(expected_files))
lum_list      <- vector("list", length(expected_files))
sp_list       <- vector("list", length(expected_files))
sp_sum_list   <- vector("list", length(expected_files))
ctry_list     <- vector("list", length(expected_files))
nuts2_list    <- vector("list", length(expected_files))
ledger_list   <- vector("list", length(expected_files))
fb_list       <- vector("list", length(expected_files))

for (i in seq_along(expected_files)) {
  pkg <- readRDS(expected_files[i])
  if (!identical(pkg$run_id, PASTURE_RESULT_TAG)) {
    stop(sprintf("[P13] Run ID mismatch in %s: expected '%s', got '%s'.",
                 expected_files[i], PASTURE_RESULT_TAG, pkg$run_id))
  }
  reg <- pkg$region
  yr  <- pkg$year

  cell_list[[i]]   <- copy(pkg$cell_summary)[, `:=`(region = reg, year = yr, run_id = pkg$run_id)]
  lum_list[[i]]    <- copy(pkg$lum_summary)[, `:=`(region = reg, year = yr, run_id = pkg$run_id)]
  sp_list[[i]]     <- copy(pkg$species_lum_alloc)[, `:=`(region = reg, year = yr, run_id = pkg$run_id)]
  sp_sum_list[[i]] <- copy(pkg$species_summary)[, run_id := pkg$run_id]
  ctry_list[[i]]   <- copy(pkg$country_summary)[, run_id := pkg$run_id]
  nuts2_list[[i]]  <- copy(pkg$nuts2_summary)[, run_id := pkg$run_id]
  ledger_list[[i]] <- copy(pkg$ledger)
  fb_list[[i]]     <- copy(pkg$fallbacks)
}

cell_all    <- rbindlist(cell_list)
lum_all     <- rbindlist(lum_list)
sp_alloc    <- rbindlist(sp_list)
species_all <- rbindlist(sp_sum_list)
country_all <- rbindlist(ctry_list)
nuts2_all   <- rbindlist(nuts2_list)
ledger_all  <- rbindlist(c(list(rbindlist(manifest_ledger)), ledger_list), fill = TRUE)
fallbacks_all <- rbindlist(c(list(rbindlist(manifest_fallbacks)), fb_list), fill = TRUE)

assert_contract(cell_all,    "P13/cell_all",    key_cols = c("region", "year", "CELLCODE"))
assert_contract(lum_all,     "P13/lum_all",     key_cols = c("region", "year", "CELLCODE", "LUM.class"))
assert_contract(sp_alloc,    "P13/sp_alloc",    key_cols = c("region", "year", "CELLCODE", "LUM.class", "species"))
assert_contract(species_all, "P13/species_all", key_cols = c("region", "year", "species"))
assert_contract(country_all, "P13/country_all", key_cols = c("region", "year"))

## Cross-table conservation assertions (no double counting)
stopifnot(abs(sum(cell_all$area_ha) - sum(lum_all$area_ha)) <= 1e-6 * sum(lum_all$area_ha))
stopifnot(abs(sum(cell_all$CO2_SOC_t) - sum(lum_all$CO2_SOC_t)) <= 1e-6 * max(1, sum(abs(lum_all$CO2_SOC_t))))
stopifnot(abs(sum(cell_all$LSU_total) - sum(sp_alloc$LSU)) <= 1e-6 * sum(sp_alloc$LSU))

agg_dir  <- file.path("output", PASTURE_RESULT_TAG, "aggregated")
agg_path <- file.path(agg_dir, sprintf("%s_pasture.rds", PASTURE_RESULT_TAG))
save_rds_atomic(
  list(
    run_id        = PASTURE_RESULT_TAG,
    cell_all      = cell_all,
    lum_all       = lum_all,
    species_alloc = sp_alloc,
    species_all   = species_all,
    country_all   = country_all,
    nuts2_all     = nuts2_all,
    ledger        = ledger_all,
    fallbacks     = fallbacks_all
  ),
  agg_path
)

## Write canonical Apache Parquet tables + JSON sidecars (spatial-downscaling.md Principle 8)
pq_tables <- list(
  cell_all        = cell_all,
  lum_all         = lum_all,
  species_alloc   = sp_alloc,
  species_summary = species_all,
  country_summary = country_all,
  nuts2_summary   = nuts2_all
)
out_band_cat <- file.path("output", PASTURE_RESULT_TAG, "pasture_band_catalogue.csv")
manifest_rel <- file.path("output", PASTURE_RESULT_TAG, "run_manifest.json")
for (nm in names(pq_tables)) {
  pq_f <- file.path(agg_dir, sprintf("%s_%s.parquet", PASTURE_RESULT_TAG, nm))
  save_parquet_atomic(pq_tables[[nm]], pq_f)
  write_output_sidecar(
    data_path     = pq_f,
    product_name  = paste0("pasture_aggregated_", nm),
    run_id        = PASTURE_RESULT_TAG,
    year          = paste(sort(unique(country_all$year)), collapse = ","),
    spatial_meta  = list(crs_epsg = "EPSG:3035", grid_id_col = "CELLCODE", n_rows = nrow(pq_tables[[nm]])),
    legend_file   = if (file.exists(out_band_cat)) out_band_cat else NULL,
    manifest_path = manifest_rel
  )
}

message(sprintf("  [P13] Combined %d country x year files into %s (+ 6 Parquet tables)", length(expected_files), agg_path))

