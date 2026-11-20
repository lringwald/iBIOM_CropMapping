##### PASTURE P03: load shared inputs once before the country x year loop

library(data.table)
library(dplyr)

check_file_hydrated(country.grid.path, check_magic = TRUE)
check_file_hydrated(EPIC.grass.pq.path, check_magic = TRUE)
check_file_hydrated(EPIC.grass.ref.pq.path, check_magic = TRUE)
check_file_hydrated(faostat.accounts.pq.path, check_magic = TRUE)
check_file_hydrated(eurostat.priors.lsk.pq.path, check_magic = TRUE)
check_file_hydrated(eurostat.priors.milk.pq.path, check_magic = TRUE)
check_file_hydrated(eurostat.priors.mfa.pq.path, check_magic = TRUE)
check_file_hydrated(grid.1km.map.path, check_magic = TRUE)
check_file_hydrated(band.catalogue.csv, check_magic = FALSE)

country_grid <- readRDS(country.grid.path) %>%
  arrange(desc(years), lama.regs) %>%
  filter(years %in% as.integer(PASTURE_RUN_YEARS))

if (nrow(country_grid) == 0L) {
  stop("[P03] No rows in country_grid match PASTURE_RUN_YEARS = ",
       paste(PASTURE_RUN_YEARS, collapse = ", "))
}

## Explicit exclusion of Cyprus (CY): 0 rows in one_km_to_lower_resolution_mapping_NUTS_2016_imputed.rds
if ("CY" %in% country_grid$lama.regs) {
  cy_years <- unique(country_grid$years[country_grid$lama.regs == "CY"])
  for (cy_y in cy_years) {
    manifest_fallbacks[[length(manifest_fallbacks) + 1L]] <- new_fallback_entry(
      stage = "P03_load_shared", region = "CY", year = cy_y,
      kind = "excluded_country", requested = "CY in country_grid", used = "skipped",
      affected_share = 1.0,
      reason = "CY has 0 pixels in 1 km grid mapping and is excluded from FAOSTAT Europe bulk files"
    )
  }
  message("  [P03] Excluding CY (0 pixels in 1 km grid mapping; logged in manifest).")
  country_grid <- country_grid %>% filter(lama.regs != "CY")
}

if (!is.null(PASTURE_COUNTRIES) && length(PASTURE_COUNTRIES) > 0L) {
  unknown_regs <- setdiff(PASTURE_COUNTRIES, unique(country_grid$lama.regs))
  if (length(unknown_regs) > 0L) {
    stop("[P03] Unknown PASTURE_COUNTRIES codes: ", paste(unknown_regs, collapse = ", "))
  }
  country_grid <- country_grid %>% filter(lama.regs %in% PASTURE_COUNTRIES)
}

if (nrow(country_grid) == 0L) {
  stop("[P03] Country grid is empty after filtering.")
}

## Load canonical Apache Parquet tables (single physical copy per input, Principle 13)
EPIC_grass_params <- as.data.table(arrow::read_parquet(EPIC.grass.pq.path))
EPIC_simu_ref     <- as.data.table(arrow::read_parquet(EPIC.grass.ref.pq.path))

faostat_accounts  <- as.data.table(arrow::read_parquet(faostat.accounts.pq.path))

eurostat_priors <- list(
  nuts2_livestock = as.data.table(arrow::read_parquet(eurostat.priors.lsk.pq.path)),
  nuts2_milk      = as.data.table(arrow::read_parquet(eurostat.priors.milk.pq.path)),
  nat_mfa         = as.data.table(arrow::read_parquet(eurostat.priors.mfa.pq.path))
)
pasture_constants <- load_pasture_constants(pasture.params.csv)
lum_grass_legend  <- fread(lum.grass.class.csv)
band_catalogue    <- fread(band.catalogue.csv)
assert_contract(band_catalogue, "P03/pasture_band_catalogue",
                req_cols = c("band_index", "band_name", "variable_type", "value_semantics", "unit", "datatype", "nodata"),
                key_cols = "band_name")
gwp_pair          <- resolve_gwp(GWP_VERSION, pasture_constants)

## Load 1 km master grid lookup and verify 1:1 CELLCODE uniqueness
grid_1km_all <- as.data.table(readRDS(grid.1km.map.path))
grid_1km_all <- grid_1km_all[, .(
  PNTIDupdt = as.integer(PNTIDupdt),
  SimUID    = as.integer(SimUID),
  NUTS0     = as.character(NUTS0),
  NUTS2     = as.character(NUTS2),
  EOFORIGIN = floor(as.numeric(x) / 1000) * 1000,
  NOFORIGIN = floor(as.numeric(y) / 1000) * 1000
)]
grid_1km_all[, CELLCODE := make_cellcode_1km(EOFORIGIN, NOFORIGIN)]
assert_contract(
  grid_1km_all, "P03/grid_1km_all",
  req_cols = c("PNTIDupdt", "SimUID", "NUTS0", "NUTS2", "EOFORIGIN", "NOFORIGIN", "CELLCODE"),
  key_cols = "CELLCODE"
)

## Precompute EU mean EPIC grass values by LUM.class for explicit fallback if a whole country lacks EPIC coverage
epic_eu_means <- EPIC_grass_params[, .(
  YLDF_eu                  = mean(YLDF, na.rm = TRUE),
  OCPD_eu                  = mean(OCPD, na.rm = TRUE),
  dOCPD_eu                 = mean(dOCPD, na.rm = TRUE),
  NFERT_eu                 = mean(NFERT, na.rm = TRUE),
  FCO_eu                   = mean(FCO, na.rm = TRUE),
  RSDC_eu                  = mean(RSDC, na.rm = TRUE),
  NFERT_org_est_kg_ha_eu   = mean(NFERT_org_est_kg_ha, na.rm = TRUE),
  NFERT_synth_est_kg_ha_eu = mean(NFERT_synth_est_kg_ha, na.rm = TRUE)
), by = LUM.class]

message(sprintf("  [P03] Loaded %d 1 km grid cells, %d EPIC grass rows, %d country x year jobs.",
                nrow(grid_1km_all), nrow(EPIC_grass_params), nrow(country_grid)))

