##### SUPPORT: prepare FAOSTAT national ruminant accounts & per-head coefficients
##### Sources (read-only staged ZIPs in faostat.raw.dir):
#####   - Production_Crops_Livestock_E_Europe.zip      (QCL)
#####   - Emissions_livestock_E_Europe.zip             (GLE)
#####   - Environment_LivestockManure_E_Europe.zip     (EMN)
#####   - Environment_LivestockPatterns_E_Europe.zip   (EK)
##### Adheres to data-integrity.md (flag preservation, no silent coercion) &
##### data-pipelines.md (unique keys, explicit contracts, atomic write).

library(data.table)
library(countrycode)

if (!exists("INPUT_DIR")) {
  if (!file.exists("user_config.R")) stop("user_config.R not found; run from repo root.")
  source("user_config.R")
  source("codes/01_settings.R")
  source("codes/support/fun_pasture_contracts.R")
}

read_faostat_zip_csv <- function(zip_path, csv_pattern, yrs) {
  check_file_hydrated(zip_path, check_magic = TRUE)
  td <- tempfile("faostat_")
  dir.create(td, recursive = TRUE, showWarnings = FALSE)
  on.exit(unlink(td, recursive = TRUE), add = TRUE)

  fl <- utils::unzip(zip_path, list = TRUE)$Name
  target_csv <- fl[grepl(csv_pattern, fl)][1]
  if (is.na(target_csv)) {
    stop(sprintf("[prep_faostat_accounts] Pattern '%s' not found in %s", csv_pattern, zip_path))
  }
  utils::unzip(zip_path, files = target_csv, exdir = td, overwrite = TRUE)
  dt <- fread(file.path(td, target_csv))

  ## Keep only target European countries matching our grid ISO2 codes
  eu28 <- c("AT","BE","BG","CY","CZ","DE","DK","EE","EL","ES","FI","FR",
            "HR","HU","IE","IT","LT","LU","LV","MT","NL","PL","PT","RO",
            "SE","SI","SK","UK")
  dt[, region := countrycode(Area, "country.name", "eurostat", warn = FALSE)]
  dt[Area == "Netherlands (Kingdom of the)", region := "NL"]
  dt[Area == "United Kingdom of Great Britain and Northern Ireland", region := "UK"]
  dt[Area == "Czechia", region := "CZ"]
  dt[Area == "Greece", region := "EL"]
  dt <- dt[region %in% eu28]

  ## Melt wide Y<year> and Y<year>F columns cleanly preserving flags
  id_cols <- intersect(c("region", "Area", "Item", "Element", "Source", "Unit"), names(dt))
  val_cols <- intersect(paste0("Y", yrs), names(dt))
  flg_cols <- intersect(paste0("Y", yrs, "F"), names(dt))
  if (length(val_cols) == 0L) {
    stop(sprintf("[prep_faostat_accounts] None of requested years (%s) found in %s",
                 paste(yrs, collapse = ", "), basename(zip_path)))
  }

  v_long <- melt(
    dt[, c(id_cols, val_cols), with = FALSE],
    id.vars = id_cols,
    measure.vars = val_cols,
    variable.name = "ycol",
    value.name = "value",
    variable.factor = FALSE
  )
  v_long[, year := as.character(sub("^Y", "", ycol))]
  v_long[, ycol := NULL]

  if (length(flg_cols) > 0L) {
    f_long <- melt(
      dt[, c(id_cols, flg_cols), with = FALSE],
      id.vars = id_cols,
      measure.vars = flg_cols,
      variable.name = "fcol",
      value.name = "flag",
      variable.factor = FALSE
    )
    f_long[, year := as.character(sub("^Y([0-9]+)F$", "\\1", fcol))]
    f_long[, fcol := NULL]
    res <- merge(v_long, f_long, by = c(id_cols, "year"), all.x = TRUE)
  } else {
    res <- v_long[, flag := NA_character_]
  }
  res[, value := as.numeric(value)]
  res
}

yrs_keep <- as.character(c(2000, 2010, 2018:2022))

consts <- load_pasture_constants(pasture.params.csv)

## 1. GLE: species stocks + CH4/N2O emissions (FAO TIER 1 & UNFCCC)
gle_zip <- file.path(faostat.raw.dir, "Emissions_livestock_E_Europe.zip")
gle_raw <- read_faostat_zip_csv(gle_zip, "^Emissions_livestock_E_Europe[.]csv$", yrs_keep)

sp_map <- c(
  "Cattle, dairy"     = "dairy_cattle",
  "Cattle, non-dairy" = "non_dairy_cattle",
  "Sheep"             = "sheep",
  "Goats"             = "goats"
)
gle_raw <- gle_raw[Item %in% names(sp_map)]
gle_raw[, species := unname(sp_map[Item])]
assert_contract(gle_raw, "prep_faostat_accounts/GLE",
                req_cols = c("region", "year", "species", "Element", "Source", "Unit", "value"),
                key_cols = c("region", "year", "species", "Element", "Source"))

pull_gle <- function(elem_name, src_name, out_col, mult = 1) {
  sub <- gle_raw[Element == elem_name & Source == src_name,
                 .(region, year, species, val = value * mult, flg = flag)]
  setnames(sub, c("val", "flg"), c(out_col, paste0(out_col, "_flag")))
  sub
}

base_keys <- unique(gle_raw[Source == "FAO TIER 1", .(region, year, species)])
acc <- copy(base_keys)

gle_specs <- list(
  list("Stocks", "FAO TIER 1", "heads", 1),
  list("Stocks", "UNFCCC", "heads_unfccc", 1),
  list("Enteric fermentation (Emissions CH4)", "FAO TIER 1", "CH4_enteric_t", 1000),
  list("Enteric fermentation (Emissions CH4)", "UNFCCC", "CH4_enteric_unfccc_t", 1000),
  list("Manure management (Emissions CH4)", "FAO TIER 1", "CH4_manure_mgt_t", 1000),
  list("Manure management (Emissions CH4)", "UNFCCC", "CH4_manure_mgt_unfccc_t", 1000),
  list("Manure management (Direct emissions N2O)", "FAO TIER 1", "N2O_manure_mgt_direct_t", 1000),
  list("Manure management (Direct emissions N2O)", "UNFCCC", "N2O_manure_mgt_direct_unfccc_t", 1000),
  list("Manure management (Indirect emissions N2O)", "FAO TIER 1", "N2O_manure_mgt_indirect_t", 1000),
  list("Manure left on pasture (Direct emissions N2O)", "FAO TIER 1", "N2O_pasture_prp_direct_t", 1000),
  list("Manure left on pasture (Indirect emissions N2O)", "FAO TIER 1", "N2O_pasture_prp_indirect_t", 1000),
  list("Manure applied to soils (Direct emissions N2O)", "FAO TIER 1", "N2O_manure_applied_direct_t", 1000),
  list("Manure applied to soils (Indirect emissions N2O)", "FAO TIER 1", "N2O_manure_applied_indirect_t", 1000)
)
for (sp in gle_specs) {
  d <- pull_gle(sp[[1]], sp[[2]], sp[[3]], sp[[4]])
  acc <- merge(acc, d, by = c("region", "year", "species"), all.x = TRUE)
}

## Drop redundant *_flag columns for secondary fields while keeping heads_flag
keep_flags <- c("heads_flag", "CH4_enteric_t_flag", "CH4_enteric_unfccc_t_flag")
drop_flags <- setdiff(grep("_flag$", names(acc), value = TRUE), keep_flags)
if (length(drop_flags) > 0L) acc[, (drop_flags) := NULL]

acc[, `:=`(
  N2O_manure_mgt_total_t     = N2O_manure_mgt_direct_t + N2O_manure_mgt_indirect_t,
  N2O_pasture_prp_total_t    = N2O_pasture_prp_direct_t + N2O_pasture_prp_indirect_t,
  N2O_manure_applied_total_t = N2O_manure_applied_direct_t + N2O_manure_applied_indirect_t
)]

## 2. EMN: N excretion & pathways (kg N)
emn_zip <- file.path(faostat.raw.dir, "Environment_LivestockManure_E_Europe.zip")
emn_raw <- read_faostat_zip_csv(emn_zip, "^Environment_LivestockManure_E_Europe[.]csv$", yrs_keep)
emn_raw <- emn_raw[Item %in% names(sp_map)]
emn_raw[, species := unname(sp_map[Item])]
assert_contract(emn_raw, "prep_faostat_accounts/EMN",
                req_cols = c("region", "year", "species", "Element", "value"),
                key_cols = c("region", "year", "species", "Element"))

emn_specs <- list(
  list("Amount excreted in manure (N content)", "N_excreted_total_kg"),
  list("Manure left on pasture (N content)", "N_left_on_pasture_kg"),
  list("Manure management (manure treated, N content)", "N_treated_mms_kg"),
  list("Manure applied to soils (N content)", "N_applied_soils_kg")
)
for (sp in emn_specs) {
  sub <- emn_raw[Element == sp[[1]], .(region, year, species, val = value)]
  setnames(sub, "val", sp[[2]])
  acc <- merge(acc, sub, by = c("region", "year", "species"), all.x = TRUE)
}

## 3. EK: official FAOSTAT Livestock Units (LSU)
ek_zip <- file.path(faostat.raw.dir, "Environment_LivestockPatterns_E_Europe.zip")
ek_raw <- read_faostat_zip_csv(ek_zip, "^Environment_LivestockPatterns_E_Europe[.]csv$", yrs_keep)
ek_lsu <- ek_raw[Element == "Stocks" & Unit == "LSU" & Item %in% c("Cattle", "Sheep", "Goats"),
                 .(region, year, Item, ek_lsu = value, ek_flag = flag)]
assert_contract(ek_lsu, "prep_faostat_accounts/EK",
                req_cols = c("region", "year", "Item", "ek_lsu"),
                key_cols = c("region", "year", "Item"))

ek_wide <- dcast(ek_lsu, region + year ~ Item, value.var = "ek_lsu")
acc <- merge(acc, ek_wide, by = c("region", "year"), all.x = TRUE)

## Split EK Cattle LSU into dairy_cattle (1.0 LSU/head, Eurostat standard) + non_dairy_cattle residual
dairy_heads_dt <- acc[species == "dairy_cattle", .(region, year, heads_dairy = heads)]
acc <- merge(acc, dairy_heads_dt, by = c("region", "year"), all.x = TRUE)

acc[, lsu := fcase(
  species == "dairy_cattle",     heads * consts[["LSU_dairy_cow_eurostat"]],
  species == "non_dairy_cattle", pmax(0, Cattle - heads_dairy * consts[["LSU_dairy_cow_eurostat"]]),
  species == "sheep",            Sheep,
  species == "goats",            Goats
)]
acc[, `:=`(
  lsu_per_head = fifelse(!is.na(heads) & heads > 0, lsu / heads, NA_real_),
  Cattle = NULL, Sheep = NULL, Goats = NULL, heads_dairy = NULL
)]

## 4. QCL: milk and meat production (tonnes)
qcl_zip <- file.path(faostat.raw.dir, "Production_Crops_Livestock_E_Europe.zip")
qcl_raw <- read_faostat_zip_csv(qcl_zip, "^Production_Crops_Livestock_E_Europe[.]csv$", yrs_keep)
qcl_prod <- qcl_raw[Element == "Production" & Unit == "t" & Item %in% c(
  "Raw milk of cattle", "Raw milk of sheep", "Raw milk of goats",
  "Meat of cattle with the bone, fresh or chilled",
  "Meat of sheep, fresh or chilled",
  "Meat of goat, fresh or chilled"
)]
assert_contract(qcl_prod, "prep_faostat_accounts/QCL",
                req_cols = c("region", "year", "Item", "value"),
                key_cols = c("region", "year", "Item"))

qcl_w <- dcast(qcl_prod, region + year ~ Item, value.var = "value")
qcl_f <- dcast(qcl_prod, region + year ~ Item, value.var = "flag")
setnames(qcl_f, setdiff(names(qcl_f), c("region", "year")),
         paste0(setdiff(names(qcl_f), c("region", "year")), "__flag"))

acc <- merge(acc, qcl_w, by = c("region", "year"), all.x = TRUE)
acc <- merge(acc, qcl_f, by = c("region", "year"), all.x = TRUE)

cattle_tot_dt <- acc[species %in% c("dairy_cattle", "non_dairy_cattle"),
                     .(cattle_tot_heads = sum(heads, na.rm = TRUE)),
                     by = .(region, year)]
acc <- merge(acc, cattle_tot_dt, by = c("region", "year"), all.x = TRUE)

acc[, milk_t := fcase(
  species == "dairy_cattle",     `Raw milk of cattle`,
  species == "non_dairy_cattle", 0,
  species == "sheep",            `Raw milk of sheep`,
  species == "goats",            `Raw milk of goats`
)]
acc[, milk_flag := fcase(
  species == "dairy_cattle",     `Raw milk of cattle__flag`,
  species == "non_dairy_cattle", "fixed_zero",
  species == "sheep",            `Raw milk of sheep__flag`,
  species == "goats",            `Raw milk of goats__flag`
)]
acc[, meat_t := fcase(
  species %in% c("dairy_cattle", "non_dairy_cattle"),
    fifelse(cattle_tot_heads > 0,
            `Meat of cattle with the bone, fresh or chilled` * (heads / cattle_tot_heads),
            NA_real_),
  species == "sheep", `Meat of sheep, fresh or chilled`,
  species == "goats", `Meat of goat, fresh or chilled`
)]
acc[, meat_flag := fcase(
  species %in% c("dairy_cattle", "non_dairy_cattle"), `Meat of cattle with the bone, fresh or chilled__flag`,
  species == "sheep", `Meat of sheep, fresh or chilled__flag`,
  species == "goats", `Meat of goat, fresh or chilled__flag`
)]

qcl_drop <- grep("^(Raw milk|Meat of )|__flag$|^cattle_tot_heads$", names(acc), value = TRUE)
acc[, (qcl_drop) := NULL]

## Derive exact per-head yields and emission / N rates
acc[, `:=`(
  milk_t_head                 = fifelse(!is.na(heads) & heads > 0, milk_t / heads, NA_real_),
  meat_t_head                 = fifelse(!is.na(heads) & heads > 0, meat_t / heads, NA_real_),
  CH4_enteric_t_head          = fifelse(!is.na(heads) & heads > 0, CH4_enteric_t / heads, NA_real_),
  CH4_manure_mgt_t_head       = fifelse(!is.na(heads) & heads > 0, CH4_manure_mgt_t / heads, NA_real_),
  N2O_manure_mgt_dir_t_head   = fifelse(!is.na(heads) & heads > 0, N2O_manure_mgt_direct_t / heads, NA_real_),
  N2O_manure_mgt_ind_t_head   = fifelse(!is.na(heads) & heads > 0, N2O_manure_mgt_indirect_t / heads, NA_real_),
  N2O_pasture_prp_dir_t_head  = fifelse(!is.na(heads) & heads > 0, N2O_pasture_prp_direct_t / heads, NA_real_),
  N2O_pasture_prp_ind_t_head  = fifelse(!is.na(heads) & heads > 0, N2O_pasture_prp_indirect_t / heads, NA_real_),
  N2O_manure_apl_dir_t_head   = fifelse(!is.na(heads) & heads > 0, N2O_manure_applied_direct_t / heads, NA_real_),
  N2O_manure_apl_ind_t_head   = fifelse(!is.na(heads) & heads > 0, N2O_manure_applied_indirect_t / heads, NA_real_),
  N_excreted_kg_head          = fifelse(!is.na(heads) & heads > 0, N_excreted_total_kg / heads, NA_real_),
  N_left_on_pasture_kg_head   = fifelse(!is.na(heads) & heads > 0, N_left_on_pasture_kg / heads, NA_real_),
  N_treated_mms_kg_head       = fifelse(!is.na(heads) & heads > 0, N_treated_mms_kg / heads, NA_real_),
  N_applied_soils_kg_head     = fifelse(!is.na(heads) & heads > 0, N_applied_soils_kg / heads, NA_real_),
  CH4_enteric_unfccc_t_head   = fifelse(!is.na(heads) & heads > 0 & !is.na(CH4_enteric_unfccc_t), CH4_enteric_unfccc_t / heads, NA_real_),
  CH4_manure_mgt_unfccc_t_head= fifelse(!is.na(heads) & heads > 0 & !is.na(CH4_manure_mgt_unfccc_t), CH4_manure_mgt_unfccc_t / heads, NA_real_),
  N2O_manure_mgt_dir_unfccc_t_head = fifelse(!is.na(heads) & heads > 0 & !is.na(N2O_manure_mgt_direct_unfccc_t), N2O_manure_mgt_direct_unfccc_t / heads, NA_real_)
)]

assert_contract(
  acc, "prep_faostat_accounts/out",
  req_cols = c("region", "year", "species", "heads", "lsu", "lsu_per_head",
               "milk_t", "meat_t", "CH4_enteric_t", "CH4_manure_mgt_t",
               "N2O_manure_mgt_total_t", "N2O_pasture_prp_total_t", "N2O_manure_applied_total_t",
               "N_excreted_total_kg"),
  key_cols = c("region", "year", "species"),
  non_neg_cols = c("heads", "lsu")
)

meta <- list(
  created_utc = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  zip_md5 = unname(tools::md5sum(c(gle_zip, emn_zip, ek_zip, qcl_zip))),
  zip_files = basename(c(gle_zip, emn_zip, ek_zip, qcl_zip))
)

save_rds_atomic(list(accounts = acc, metadata = meta), faostat.accounts.path)
save_parquet_atomic(acc, faostat.accounts.pq.path)
write_output_sidecar(
  data_path    = faostat.accounts.pq.path,
  product_name = "faostat_national_accounts",
  run_id       = "raw_ingest",
  spatial_meta = list(unit_id = "region x year x species"),
  validation_summary = list(n_rows = nrow(acc), n_countries = uniqueN(acc$region), zip_files = meta$zip_files)
)
message(sprintf("  [prep_faostat_accounts] Saved %d (region x year x species) rows across %d countries to %s (+ .rds)",
                nrow(acc), uniqueN(acc$region), faostat.accounts.pq.path))

