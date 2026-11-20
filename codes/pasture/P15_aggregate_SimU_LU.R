##### PASTURE P15: aggregate 1 km results to SimUID (conservation-checked)

library(data.table)

agg_path <- file.path("output", PASTURE_RESULT_TAG, "aggregated", sprintf("%s_pasture.rds", PASTURE_RESULT_TAG))
agg <- readRDS(agg_path)
if (!identical(agg$run_id, PASTURE_RESULT_TAG)) stop("[P15] Run ID mismatch.")

lum_all <- copy(agg$lum_all)
wm_safe <- function(x, w) if (all(is.na(x)) || sum(w[!is.na(x)]) == 0) NA_real_ else stats::weighted.mean(x, w, na.rm = TRUE)

simu_lum <- lum_all[, .(
  area_ha                    = sum(area_ha),
  area_km2                   = sum(area_km2),
  forage_dm_t                = sum(forage_dm_t),
  YLDF_mean                  = sum(forage_dm_t) / sum(area_ha),
  OCPD_mean                  = wm_safe(OCPD, area_ha),
  dOCPD_mean                 = wm_safe(dOCPD, area_ha),
  NFERT_mean                 = wm_safe(NFERT, area_ha),
  LSU_total                  = sum(LSU_allocated),
  heads_total                = sum(heads_total),
  dairy_cattle_heads         = sum(dairy_cattle_heads),
  non_dairy_cattle_heads     = sum(non_dairy_cattle_heads),
  sheep_heads                = sum(sheep_heads),
  goats_heads                = sum(goats_heads),
  milk_t                     = sum(milk_t),
  meat_t                     = sum(meat_t),
  CH4_enteric_t              = sum(CH4_enteric_t),
  CH4_manure_mgt_t           = sum(CH4_manure_mgt_t),
  N2O_manure_mgt_total_t     = sum(N2O_manure_mgt_total_t),
  N2O_pasture_prp_total_t    = sum(N2O_pasture_prp_total_t),
  N2O_manure_applied_total_t = sum(N2O_manure_applied_total_t),
  N2O_synth_fert_total_t     = sum(N2O_synth_fert_total_t),
  CO2_SOC_t                  = sum(CO2_SOC_t),
  GHG_livestock_CO2e_t       = sum(GHG_livestock_CO2e_t),
  GHG_pasture_soil_CO2e_t    = sum(GHG_pasture_soil_CO2e_t),
  GHG_total_CO2e_t           = sum(GHG_total_CO2e_t)
), by = .(region, year, SimUID, LUM.class)]

simu_total <- simu_lum[, .(
  area_ha              = sum(area_ha),
  forage_dm_t          = sum(forage_dm_t),
  YLDF_mean            = sum(forage_dm_t) / sum(area_ha),
  OCPD_mean            = wm_safe(OCPD_mean, area_ha),
  dOCPD_mean           = wm_safe(dOCPD_mean, area_ha),
  LSU_total            = sum(LSU_total),
  heads_total          = sum(heads_total),
  milk_t               = sum(milk_t),
  meat_t               = sum(meat_t),
  GHG_livestock_CO2e_t = sum(GHG_livestock_CO2e_t),
  GHG_pasture_soil_CO2e_t = sum(GHG_pasture_soil_CO2e_t),
  GHG_total_CO2e_t     = sum(GHG_total_CO2e_t)
), by = .(region, year, SimUID)]

assert_contract(simu_lum,   "P15/simu_lum",   key_cols = c("region", "year", "SimUID", "LUM.class"))
assert_contract(simu_total, "P15/simu_total", key_cols = c("region", "year", "SimUID"))

## Exact conservation assertions against 1 km grid totals
stopifnot(abs(sum(simu_total$area_ha) - sum(lum_all$area_ha)) <= 1e-6 * sum(lum_all$area_ha))
stopifnot(abs(sum(simu_total$LSU_total) - sum(lum_all$LSU_allocated)) <= 1e-6 * sum(lum_all$LSU_allocated))
stopifnot(abs(sum(simu_total$GHG_total_CO2e_t) - sum(lum_all$GHG_total_CO2e_t)) <= 1e-6 * max(1, sum(abs(lum_all$GHG_total_CO2e_t))))

simu_dir     <- file.path("output", PASTURE_RESULT_TAG, "simu_res")
simu_path    <- file.path(simu_dir, sprintf("%s_SimU_res.rds", PASTURE_RESULT_TAG))
simu_lum_pq  <- file.path(simu_dir, sprintf("%s_simu_lum.parquet", PASTURE_RESULT_TAG))
simu_tot_pq  <- file.path(simu_dir, sprintf("%s_simu_total.parquet", PASTURE_RESULT_TAG))
save_rds_atomic(
  list(run_id = PASTURE_RESULT_TAG, simu_lum = simu_lum, simu_total = simu_total),
  simu_path
)
save_parquet_atomic(simu_lum, simu_lum_pq)
save_parquet_atomic(simu_total, simu_tot_pq)
manifest_rel <- file.path("output", PASTURE_RESULT_TAG, "run_manifest.json")
write_output_sidecar(
  data_path = simu_lum_pq, product_name = "pasture_simu_lum_parquet",
  run_id = PASTURE_RESULT_TAG, year = paste(sort(unique(simu_lum$year)), collapse = ","),
  spatial_meta = list(crs_epsg = "EPSG:3035", unit_id = "SimUID x LUM.class", n_rows = nrow(simu_lum)),
  manifest_path = manifest_rel
)
write_output_sidecar(
  data_path = simu_tot_pq, product_name = "pasture_simu_total_parquet",
  run_id = PASTURE_RESULT_TAG, year = paste(sort(unique(simu_total$year)), collapse = ","),
  spatial_meta = list(crs_epsg = "EPSG:3035", unit_id = "SimUID", n_rows = nrow(simu_total)),
  manifest_path = manifest_rel
)
message(sprintf("  [P15] Saved SimU aggregation (%d SimUID rows) to %s (+ Parquet & JSON sidecars)", nrow(simu_total), simu_path))

