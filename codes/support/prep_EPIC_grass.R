##### SUPPORT: standalone processor for raw EPIC-IIASA Grassland parameters
##### Run standalone: Rscript codes/support/prep_EPIC_grass.R
##### Processes:
#####   1. All 12 LUM scenarios (LUM15..LUM26) across YLDF, dOCPD (OCPD.init, dOCPD),
#####      NFERT, FCO, RSDC (including epic_area_ha = Area.ha), decomposing organic vs.
#####      residual synthetic N. Writes EPIC_grass_params.parquet (+ .rds + .json sidecar).
#####   2. All 5 REF scenario files (LAMASUS_EPIC_Grassland_REF_mean_*.txt) and
#####      Auxiliary/GRS_LUM_AreaHa_BySimUID.txt (X15..X26, GRS.Area), verifying
#####      internal area summation consistency and writing EPIC_grass_simu_ref.parquet
#####      (+ .rds + .json sidecar) for independent multi-resolution SimUID benchmarking.

library(data.table)

if (!exists("INPUT_DIR")) {
  if (!file.exists("user_config.R")) stop("user_config.R not found; run from repo root.")
  source("user_config.R")
  source("codes/01_settings.R")
  source("codes/support/fun_pasture_contracts.R")
}

read_epic_grass_dir <- function(sub_dir, var_tag) {
  dir_path <- file.path(EPIC.grass.raw.path, sub_dir)
  files <- sort(list.files(dir_path, pattern = paste0("_", var_tag, "[.]txt$"), full.names = TRUE))
  files <- grep("REF|ReadMe", files, invert = TRUE, value = TRUE)
  if (length(files) != 12L) {
    stop(sprintf("[prep_EPIC_grass] Expected 12 LUM files for '%s' in %s, found %d.",
                 var_tag, dir_path, length(files)))
  }
  lapply(files, check_file_hydrated, check_magic = FALSE)
  dt <- rbindlist(lapply(files, fread))
  assert_contract(dt, paste0("prep_EPIC_grass/", var_tag),
                  req_cols = c("SimUID", "Scen", "Area.ha"),
                  key_cols = c("SimUID", "Scen"))
  dt
}

yl_dt <- read_epic_grass_dir("YLDF", "YLDF")[, .(SimUID, Scen, epic_area_ha = as.numeric(Area.ha), YLDF = as.numeric(YLDF))]
oc_dt <- read_epic_grass_dir("Externalities", "dOCPD")[, .(SimUID, Scen, OCPD = as.numeric(OCPD.init), dOCPD = as.numeric(dOCPD))]
nf_dt <- read_epic_grass_dir("Externalities", "NFERT")[, .(SimUID, Scen, NFERT = as.numeric(NFERT))]
fc_dt <- read_epic_grass_dir("Externalities", "FCO")[, .(SimUID, Scen, FCO = as.numeric(FCO))]
rs_dt <- read_epic_grass_dir("Externalities", "RSDC")[, .(SimUID, Scen, RSDC = as.numeric(RSDC))]

epic_grass <- Reduce(function(a, b) merge(a, b, by = c("SimUID", "Scen"), all = FALSE),
                     list(yl_dt, oc_dt, nf_dt, fc_dt, rs_dt))

if (nrow(epic_grass) != nrow(yl_dt)) {
  stop(sprintf("[prep_EPIC_grass] Inner merge dropped rows: YLDF=%d vs merged=%d",
               nrow(yl_dt), nrow(epic_grass)))
}

epic_grass[, LUM.class := as.integer(sub("^LUM", "", Scen))]
n_nonfin_ocpd <- sum(!is.finite(epic_grass$OCPD))
if (n_nonfin_ocpd > 0L) {
  message(sprintf("  [prep_EPIC_grass] Converting %d non-finite (Inf/NaN) OCPD entries to NA_real_.", n_nonfin_ocpd))
  epic_grass[!is.finite(OCPD), OCPD := NA_real_]
}
n_na_docpd <- sum(!is.finite(epic_grass$dOCPD))
if (n_na_docpd > 0L) {
  message(sprintf("  [prep_EPIC_grass] Converting %d missing/non-finite dOCPD entries to 0.", n_na_docpd))
  epic_grass[!is.finite(dOCPD), dOCPD := 0]
}

consts  <- load_pasture_constants(pasture.params.csv)
lum_cls <- fread(lum.grass.class.csv)
assert_contract(lum_cls, "prep_EPIC_grass/lum_grass_classes",
                req_cols = c("LUM.class", "grazing_mode", "allow_synth_nfert"),
                key_cols = "LUM.class")

epic_grass <- merge(
  epic_grass,
  lum_cls[, .(LUM.class, grazing_mode, allow_synth_nfert)],
  by = "LUM.class", all.x = TRUE
)
if (any(is.na(epic_grass$grazing_mode))) {
  stop("[prep_EPIC_grass] Unmapped LUM.class in EPIC Grassland files.")
}

cn_ratio <- consts[["manure_CN_ratio_default"]]
epic_grass[, `:=`(
  NFERT_org_est_kg_ha   = pmin(NFERT, FCO / cn_ratio),
  NFERT_synth_est_kg_ha = ifelse(allow_synth_nfert, pmax(0, NFERT - pmin(NFERT, FCO / cn_ratio)), 0)
)]
epic_grass[, `:=`(Scen = NULL, allow_synth_nfert = NULL)]
setorder(epic_grass, SimUID, LUM.class)

assert_contract(
  epic_grass, "prep_EPIC_grass/out",
  req_cols = c("SimUID", "LUM.class", "epic_area_ha", "YLDF", "OCPD", "dOCPD",
               "NFERT", "FCO", "RSDC", "NFERT_org_est_kg_ha", "NFERT_synth_est_kg_ha", "grazing_mode"),
  key_cols = c("SimUID", "LUM.class"),
  non_neg_cols = c("epic_area_ha", "YLDF", "OCPD", "NFERT", "FCO", "RSDC",
                   "NFERT_org_est_kg_ha", "NFERT_synth_est_kg_ha")
)

save_rds_atomic(epic_grass, EPIC.grass.path)
save_parquet_atomic(epic_grass, EPIC.grass.pq.path)
write_output_sidecar(
  data_path    = EPIC.grass.pq.path,
  product_name = "EPIC_grass_params",
  run_id       = "raw_ingest",
  spatial_meta = list(crs_epsg = "EPSG:3035", unit_id = "SimUID x LUM.class", nodata = NULL),
  legend_file  = lum.grass.class.csv,
  validation_summary = list(n_rows = nrow(epic_grass), n_simuid = uniqueN(epic_grass$SimUID))
)

## ── Process REF files & Auxiliary/GRS_LUM_AreaHa_BySimUID.txt ───────────────
aux_file <- file.path(EPIC.grass.raw.path, "Auxiliary/GRS_LUM_AreaHa_BySimUID.txt")
ref_files <- list(
  YLDF  = file.path(EPIC.grass.raw.path, "YLDF/LAMASUS_EPIC_Grassland_REF_mean_YLDF.txt"),
  dOCPD = file.path(EPIC.grass.raw.path, "Externalities/LAMASUS_EPIC_Grassland_REF_mean_dOCPD.txt"),
  NFERT = file.path(EPIC.grass.raw.path, "Externalities/LAMASUS_EPIC_Grassland_REF_mean_NFERT.txt"),
  FCO   = file.path(EPIC.grass.raw.path, "Externalities/LAMASUS_EPIC_Grassland_REF_mean_FCO.txt"),
  RSDC  = file.path(EPIC.grass.raw.path, "Externalities/LAMASUS_EPIC_Grassland_REF_mean_RSDC.txt")
)
lapply(c(list(aux_file), ref_files), check_file_hydrated, check_magic = FALSE)

aux_dt <- fread(aux_file)
x_cols <- paste0("X", 15:26)
x_mgt_cols <- paste0("X", 15:25)
assert_contract(aux_dt, "prep_EPIC_grass/aux_GRS_LUM_AreaHa",
                req_cols = c("SimUID", x_cols, "GRS.Area"),
                key_cols = "SimUID",
                non_neg_cols = c(x_cols, "GRS.Area"))

aux_sum_err <- max(abs(rowSums(aux_dt[, ..x_cols]) - aux_dt$GRS.Area))
if (aux_sum_err > 1e-2) {
  stop(sprintf("[prep_EPIC_grass] GRS_LUM_AreaHa_BySimUID row sum mismatch: max diff = %.4f ha", aux_sum_err))
}
aux_dt[, `:=`(
  epic_managed_grass_ha   = rowSums(.SD),
  epic_unmanaged_26_ha    = as.numeric(X26),
  epic_total_grass_ha     = as.numeric(GRS.Area)
), .SDcols = x_mgt_cols]

r_yl <- fread(ref_files$YLDF)[, .(SimUID, ref_area_ha = as.numeric(Area.ha), YLDF_ref = as.numeric(YLDF))]
r_oc <- fread(ref_files$dOCPD)[, .(SimUID, OCPD_ref = as.numeric(OCPD.init), dOCPD_ref = as.numeric(dOCPD))]
r_nf <- fread(ref_files$NFERT)[, .(SimUID, NFERT_ref = as.numeric(NFERT))]
r_fc <- fread(ref_files$FCO)[, .(SimUID, FCO_ref = as.numeric(FCO))]
r_rs <- fread(ref_files$RSDC)[, .(SimUID, RSDC_ref = as.numeric(RSDC))]
for (dt_ref in list(r_yl, r_oc, r_nf, r_fc, r_rs)) {
  assert_contract(dt_ref, "prep_EPIC_grass/REF", req_cols = "SimUID", key_cols = "SimUID")
}

epic_simu_ref <- Reduce(
  function(a, b) merge(a, b, by = "SimUID", all = FALSE),
  list(aux_dt[, c("SimUID", "epic_managed_grass_ha", "epic_unmanaged_26_ha", "epic_total_grass_ha", x_cols), with = FALSE],
       r_yl, r_oc, r_nf, r_fc, r_rs)
)
epic_simu_ref[!is.finite(OCPD_ref), OCPD_ref := NA_real_]
epic_simu_ref[!is.finite(dOCPD_ref), dOCPD_ref := 0]
epic_simu_ref[, forage_dm_ref_t := epic_total_grass_ha * YLDF_ref]
setorder(epic_simu_ref, SimUID)

assert_contract(
  epic_simu_ref, "prep_EPIC_grass/simu_ref_out",
  req_cols = c("SimUID", "epic_managed_grass_ha", "epic_unmanaged_26_ha", "epic_total_grass_ha",
               "YLDF_ref", "forage_dm_ref_t", "OCPD_ref", "dOCPD_ref", "NFERT_ref", "FCO_ref", "RSDC_ref"),
  key_cols = "SimUID",
  non_neg_cols = c("epic_managed_grass_ha", "epic_unmanaged_26_ha", "epic_total_grass_ha", "YLDF_ref", "forage_dm_ref_t")
)

save_rds_atomic(epic_simu_ref, EPIC.grass.ref.path)
save_parquet_atomic(epic_simu_ref, EPIC.grass.ref.pq.path)
write_output_sidecar(
  data_path    = EPIC.grass.ref.pq.path,
  product_name = "EPIC_grass_simu_ref",
  run_id       = "raw_ingest",
  spatial_meta = list(crs_epsg = "EPSG:3035", unit_id = "SimUID", nodata = NULL),
  legend_file  = lum.grass.class.csv,
  validation_summary = list(n_simuid = nrow(epic_simu_ref), max_grs_area_sum_diff_ha = aux_sum_err)
)

message(sprintf("  [prep_EPIC_grass] Saved %d SimUID x LUM rows (%s) and %d SimUID REF benchmark rows (%s)",
                nrow(epic_grass), EPIC.grass.pq.path, nrow(epic_simu_ref), EPIC.grass.ref.pq.path))
