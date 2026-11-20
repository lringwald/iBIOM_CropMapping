##### SUPPORT: prepare Eurostat NUTS2 spatial priors & EW-MFA external benchmark
##### Datasets (Eurostat API via `eurostat` package, cached to eurostat.priors.path):
#####   - ef_lsk_bovine, ef_lsk_sheep, ef_lsk_goats (NUTS2 livestock heads, HD)
#####   - agr_r_milkpr (NUTS2 raw cow milk production, 1000 t -> t)
#####   - env_ac_mfa   (NUTS0 MF1221 fodder crops & MF1222 grazed biomass, 1000 t at 15% moisture -> t DM)
##### Adheres to data-integrity.md (flag preservation) & data-pipelines.md (bounded year alignment, explicit crosswalk).

library(data.table)
library(eurostat)

if (!exists("INPUT_DIR")) {
  if (!file.exists("user_config.R")) stop("user_config.R not found; run from repo root.")
  source("user_config.R")
  source("codes/01_settings.R")
  source("codes/support/fun_pasture_contracts.R")
}

eu28 <- c("AT","BE","BG","CY","CZ","DE","DK","EE","EL","ES","FI","FR",
          "HR","HU","IE","IT","LT","LU","LV","MT","NL","PL","PT","RO",
          "SE","SI","SK","UK")

fetch_eurostat_dt <- function(id, filters) {
  df <- eurostat::get_eurostat(
    id = id,
    filters = filters,
    cache = FALSE,
    keepFlags = FALSE
  )
  dt <- as.data.table(df)
  dt[, values := as.numeric(values)]
  if (!"flags" %in% names(dt)) dt[, flags := NA_character_]
  dt[, year_src := as.integer(format(as.Date(time), "%Y"))]
  dt[, region := substr(geo, 1L, 2L)]
  dt
}

## Explicit NUTS2021 -> NUTS2016 code harmonization map for renamed/split/merged NUTS2 regions
## Ensures alignment with one_km_to_lower_resolution_mapping_NUTS_2016_imputed.rds (NUTS 2016)
nuts21_to_16_map <- c(
  "HR02" = "HR04", "HR05" = "HR04", "HR06" = "HR04",
  "PL91" = "PL12", "PL92" = "PL12",
  "LT01" = "LT00", "LT02" = "LT00",
  "HU11" = "HU10", "HU12" = "HU10",
  "NO08" = "NO01", "NO09" = "NO03", "NO0A" = "NO04"
)

harmonize_nuts2 <- function(geo_vec) {
  mapped <- ifelse(geo_vec %in% names(nuts21_to_16_map), unname(nuts21_to_16_map[geo_vec]), geo_vec)
  mapped
}

fss_waves <- c("2005", "2007", "2010", "2013", "2016", "2020")
base_flt <- list(statinfo = "TOTAL", fodder = "TOTAL", lsu = "TOTAL", uaarea = "TOTAL", unit = "HD", time = fss_waves)

cat("  Fetching Eurostat FSS NUTS2 livestock (ef_lsk_bovine, ef_lsk_sheep, ef_lsk_goats)...\n")
bov <- fetch_eurostat_dt("ef_lsk_bovine", c(base_flt, list(animals = c("A2000", "A2300F"))))
shp <- fetch_eurostat_dt("ef_lsk_sheep",  c(base_flt, list(animals = "A4100")))
got <- fetch_eurostat_dt("ef_lsk_goats",  c(base_flt, list(animals = "A4200")))

lsk_all <- rbindlist(list(bov, shp, got), fill = TRUE)
lsk_all <- lsk_all[region %in% eu28 & nchar(geo) == 4L & !grepl("ZZ$", geo)]
lsk_all[, NUTS2 := harmonize_nuts2(geo)]

## Pivot bovine A2000 (total cattle) and A2300F (dairy cows) to derive non_dairy_cattle
lsk_w <- dcast(
  lsk_all,
  region + NUTS2 + year_src ~ animals,
  value.var = "values",
  fun.aggregate = function(x) if (all(is.na(x))) NA_real_ else sum(x, na.rm = TRUE)
)
lsk_flg <- dcast(
  lsk_all,
  region + NUTS2 + year_src ~ animals,
  value.var = "flags",
  fun.aggregate = function(x) paste(unique(na.omit(x)), collapse = ";")
)

lsk_sp <- rbindlist(list(
  lsk_w[, .(region, NUTS2, year_src, species = "dairy_cattle",     heads_fss = A2300F)],
  lsk_w[, .(region, NUTS2, year_src, species = "non_dairy_cattle", heads_fss = pmax(0, A2000 - fifelse(is.na(A2300F), 0, A2300F)))],
  lsk_w[, .(region, NUTS2, year_src, species = "sheep",            heads_fss = A4100)],
  lsk_w[, .(region, NUTS2, year_src, species = "goats",            heads_fss = A4200)]
))

## Attach preserved flags per species
flg_sp <- rbindlist(list(
  lsk_flg[, .(region, NUTS2, year_src, species = "dairy_cattle",     fss_flag = A2300F)],
  lsk_flg[, .(region, NUTS2, year_src, species = "non_dairy_cattle", fss_flag = ifelse(nzchar(A2000), A2000, A2300F))],
  lsk_flg[, .(region, NUTS2, year_src, species = "sheep",            fss_flag = A4100)],
  lsk_flg[, .(region, NUTS2, year_src, species = "goats",            fss_flag = A4200)]
))
lsk_sp <- merge(lsk_sp, flg_sp, by = c("region", "NUTS2", "year_src", "species"), all.x = TRUE)
lsk_sp[fss_flag == "", fss_flag := NA_character_]

## Select bounded FSS wave per target year (2000, 2010, 2018; max gap <= 5 yrs)
target_years <- c(2000L, 2010L, 2018L)
wave_pref <- list(
  "2000" = c(2005L),
  "2010" = c(2010L, 2013L, 2007L),
  "2018" = c(2016L, 2020L, 2013L)
)

lsk_targets_list <- list()
fss_log_list <- list()

for (ty in target_years) {
  prefs <- wave_pref[[as.character(ty)]]
  for (reg in eu28) {
    for (sp in c("dairy_cattle", "non_dairy_cattle", "sheep", "goats")) {
      sub <- lsk_sp[region == reg & species == sp & !is.na(heads_fss)]
      chosen_wave <- NA_integer_
      for (w in prefs) {
        if (nrow(sub[year_src == w]) > 0L && sum(sub[year_src == w]$heads_fss, na.rm = TRUE) > 0) {
          chosen_wave <- w
          break
        }
      }
      if (is.na(chosen_wave)) {
        fss_log_list[[length(fss_log_list) + 1L]] <- data.table(
          region = reg, year = as.character(ty), species = sp,
          fss_wave = NA_integer_, year_gap = NA_integer_,
          n_nuts2 = 0L, status = "missing_fallback_to_national"
        )
        next
      }
      sel <- copy(sub[year_src == chosen_wave])
      tot_h <- sum(sel$heads_fss, na.rm = TRUE)
      sel[, `:=`(
        year = as.character(ty),
        fss_wave = chosen_wave,
        year_gap = abs(chosen_wave - ty),
        nuts2_share = if (tot_h > 0) heads_fss / tot_h else NA_real_
      )]
      lsk_targets_list[[length(lsk_targets_list) + 1L]] <- sel[, .(
        region, year, NUTS2, species, heads_fss, nuts2_share, fss_wave, year_gap, fss_flag
      )]
      fss_log_list[[length(fss_log_list) + 1L]] <- data.table(
        region = reg, year = as.character(ty), species = sp,
        fss_wave = chosen_wave, year_gap = abs(chosen_wave - ty),
        n_nuts2 = nrow(sel), status = "matched"
      )
    }
  }
}

nuts2_livestock <- rbindlist(lsk_targets_list)
fss_mapping_log <- rbindlist(fss_log_list)
assert_contract(
  nuts2_livestock, "prep_eurostat_priors/nuts2_livestock",
  req_cols = c("region", "year", "NUTS2", "species", "heads_fss", "nuts2_share", "fss_wave"),
  key_cols = c("region", "year", "NUTS2", "species"),
  non_neg_cols = c("heads_fss", "nuts2_share")
)

## 2. NUTS2 cow milk production (agr_r_milkpr, 1000 t -> t)
cat("  Fetching Eurostat agr_r_milkpr (NUTS2 cow milk)...\n")
mk <- fetch_eurostat_dt("agr_r_milkpr", list(time = as.character(target_years)))
mk <- mk[region %in% eu28 & nchar(geo) == 4L & !grepl("ZZ$", geo)]
mk[, NUTS2 := harmonize_nuts2(geo)]
mk <- mk[, .(
  milk_cow_t_eurostat = if (all(is.na(values))) NA_real_ else sum(values * 1000, na.rm = TRUE),
  milk_flag = paste(unique(na.omit(flags)), collapse = ";")
), by = .(region, year = as.character(year_src), NUTS2)]
mk[milk_flag == "", milk_flag := NA_character_]
assert_contract(mk, "prep_eurostat_priors/nuts2_milk",
                req_cols = c("region", "year", "NUTS2", "milk_cow_t_eurostat"),
                key_cols = c("region", "year", "NUTS2"))

## 3. National EW-MFA grazed biomass (MF1222) and fodder crops (MF1221) in t DM (15% moisture * 0.85)
cat("  Fetching Eurostat env_ac_mfa (MF1221, MF1222)...\n")
consts <- load_pasture_constants(pasture.params.csv)
dm_f <- consts[["mfa_15pct_moisture_to_dm"]]
mfa <- fetch_eurostat_dt("env_ac_mfa", list(
  material = c("MF1221", "MF1222"),
  indic_env = "DE",
  unit = "THS_T",
  geo = eu28,
  time = as.character(target_years)
))
mfa_w <- dcast(
  mfa[, .(region = geo, year = as.character(year_src), material, val_dm_t = values * 1000 * dm_f)],
  region + year ~ material,
  value.var = "val_dm_t"
)
setnames(mfa_w, c("MF1221", "MF1222"), c("mfa_fodder_crops_dm_t", "mfa_grazed_biomass_dm_t"))
assert_contract(mfa_w, "prep_eurostat_priors/nat_mfa",
                req_cols = c("region", "year", "mfa_fodder_crops_dm_t", "mfa_grazed_biomass_dm_t"),
                key_cols = c("region", "year"))

out <- list(
  nuts2_livestock = nuts2_livestock,
  nuts2_milk      = mk,
  nat_mfa         = mfa_w,
  fss_mapping_log = fss_mapping_log,
  created_utc     = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
)
save_rds_atomic(out, eurostat.priors.path)
save_parquet_atomic(nuts2_livestock, eurostat.priors.lsk.pq.path)
save_parquet_atomic(mk, eurostat.priors.milk.pq.path)
save_parquet_atomic(mfa_w, eurostat.priors.mfa.pq.path)
write_output_sidecar(
  data_path = eurostat.priors.lsk.pq.path, product_name = "eurostat_priors_nuts2_livestock",
  run_id = "raw_ingest", spatial_meta = list(unit_id = "region x year x NUTS2 x species"),
  validation_summary = list(n_rows = nrow(nuts2_livestock), fss_waves = paste(sort(unique(nuts2_livestock$fss_wave)), collapse = ","))
)
write_output_sidecar(
  data_path = eurostat.priors.milk.pq.path, product_name = "eurostat_priors_nuts2_milk",
  run_id = "raw_ingest", spatial_meta = list(unit_id = "region x year x NUTS2"),
  validation_summary = list(n_rows = nrow(mk))
)
write_output_sidecar(
  data_path = eurostat.priors.mfa.pq.path, product_name = "eurostat_priors_nat_mfa",
  run_id = "raw_ingest", spatial_meta = list(unit_id = "region x year"),
  validation_summary = list(n_rows = nrow(mfa_w))
)
message(sprintf("  [prep_eurostat_priors] Saved NUTS2 livestock (%d rows), milk (%d rows), EW-MFA (%d rows) to Parquet + %s",
                nrow(nuts2_livestock), nrow(mk), nrow(mfa_w), eurostat.priors.path))
