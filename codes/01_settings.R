##### CODE 01: settings — input paths and run options (user-specific settings are in user_config.R)

#### Author: Michael Wögerer

if (!exists("resolve_input_path", mode = "function") &&
    file.exists("codes/support/fun_pasture_contracts.R")) {
  source("codes/support/fun_pasture_contracts.R")
}

if (!exists("LUM_DIR") || is.null(LUM_DIR) || !nzchar(LUM_DIR)) {
  LUM_DIR <- Sys.getenv("LUM_DIR", "")
}
if (!exists("SHARED_INPUT_DIR") || is.null(SHARED_INPUT_DIR) || !nzchar(SHARED_INPUT_DIR)) {
  SHARED_INPUT_DIR <- Sys.getenv("SHARED_INPUT_DIR", "/mnt/wdrv/Data/preprocessed_data/iBIOM_CropMapping_input")
}

prior.path      <- file.path(INPUT_DIR, "priors/new/")
target.path     <- file.path(INPUT_DIR, "targets/")
EEA.path        <- file.path(INPUT_DIR, "EEA_1km/")
LUM.path        <- if (nzchar(LUM_DIR)) {
  LUM_DIR
} else if (dir.exists("/mnt/wdrv/iBIOM_Explorer/Land_use_and_management")) {
  "/mnt/wdrv/iBIOM_Explorer/Land_use_and_management"
} else if (dir.exists(path.expand("~/accelerator/mnt/ibiom/iBIOM_Explorer/Land_use_and_management"))) {
  path.expand("~/accelerator/mnt/ibiom/iBIOM_Explorer/Land_use_and_management")
} else {
  file.path(INPUT_DIR, "LUM_data/")
}
mapping.path    <- file.path(INPUT_DIR, "mappings/")
LUM.energy.path <- file.path(INPUT_DIR, "LUM_fit_with_energy_levels_V5/")
SimU.path       <- file.path(INPUT_DIR, "SIMU_LAEA/5arcmin_simu_world_ETRS_1989_LAEA_wsimuID.shp")
irri.path       <- file.path(INPUT_DIR, "irrigation_Bonn/Total_IR_A_2010.tif")

#### prepared inputs (created by codes/support/prep_*.R via 02_prepare_inputs.R if missing)
country.grid.path   <- if (file.exists("output/country_grid.rds")) {
  "output/country_grid.rds"
} else {
  cg_cand <- resolve_input_path("country_grid.rds", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
  if (file.exists(cg_cand)) cg_cand else "output/country_grid.rds"
}
EPIC.map.path       <- file.path(INPUT_DIR, "EPIC/MAP/EUEPIC_SimUID_1k_updt.rds")
SimU.map.path       <- file.path(mapping.path, "SimU_CR_LU_map.rds")
EPIC.yields.path    <- file.path(INPUT_DIR, "EPIC/EPIC_yields.rds")
EPIC.vars.path      <- file.path(INPUT_DIR, "EPIC/EPIC_vars.rds")
GLOBIOM.yields.path <- file.path(INPUT_DIR, "EPIC/cropyieldsOLD_GLOBIOM.rds")
GLOBIOM.vars.path   <- file.path(INPUT_DIR, "EPIC/cropvarsOLD_GLOBIOM.rds")
GLOBIOM.target.path <- file.path(target.path, "croptargets_GLOBIOM.rds")

#### additional per-ha variables carried along with the yields (by crop x management class)
#### EPIC where the crop has EPIC data, old GLOBIOM (data_crops.gdx) otherwise
extra_vars <- c("FTN", "IRGA", "OCPD", "dOCPD")  # kg N/ha, mm, t C/ha, t C/ha/yr
#### variables multiplied by the same production adjustment factor as YLD (script 11);
#### the SOC stock (OCPD) is not scaled, a soil C stock does not depend on the yield bias
scale_vars <- c("FTN", "IRGA", "dOCPD")

#### crops without own EPIC data take these variables from the EPIC data of the most similar crop
#### (same cell and management class), see codes/support/crop_crosswalk_EPIC.csv and README;
#### variables not listed here keep the crop-specific old GLOBIOM value (FTN, IRGA)
crosswalk.path <- "./codes/support/crop_crosswalk_EPIC.csv"
crosswalk_vars <- c("OCPD", "dOCPD")

#### pasture & livestock module paths (multi-root across local INPUT_DIR and SHARED_INPUT_DIR)
EPIC.grass.raw.path          <- resolve_input_path("EPIC/Grassland", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
EPIC.grass.path              <- resolve_input_path("EPIC/EPIC_grass_params.rds", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
EPIC.grass.pq.path           <- resolve_input_path("EPIC/EPIC_grass_params.parquet", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
EPIC.grass.ref.path          <- resolve_input_path("EPIC/EPIC_grass_simu_ref.rds", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
EPIC.grass.ref.pq.path       <- resolve_input_path("EPIC/EPIC_grass_simu_ref.parquet", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
grid.1km.map.path            <- resolve_input_path("mappings/one_km_to_lower_resolution_mapping_NUTS_2016_imputed.rds", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
pasture.target.path          <- resolve_input_path("targets/pasture", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
faostat.raw.dir              <- resolve_input_path("targets/pasture/faostat_raw", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
faostat.accounts.path        <- resolve_input_path("targets/pasture/faostat_national_accounts.rds", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
faostat.accounts.pq.path     <- resolve_input_path("targets/pasture/faostat_national_accounts.parquet", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
eurostat.priors.path         <- resolve_input_path("targets/pasture/eurostat_priors_nuts2.rds", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
eurostat.priors.lsk.pq.path  <- resolve_input_path("targets/pasture/eurostat_priors_nuts2_livestock.parquet", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
eurostat.priors.milk.pq.path <- resolve_input_path("targets/pasture/eurostat_priors_nuts2_milk.parquet", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
eurostat.priors.mfa.pq.path  <- resolve_input_path("targets/pasture/eurostat_priors_nat_mfa.parquet", input_dir = INPUT_DIR, shared_input_dir = SHARED_INPUT_DIR)
pasture.params.dir           <- "./codes/support/pasture_params"
pasture.params.csv           <- file.path(pasture.params.dir, "pasture_reference_constants.csv")
lum.grass.class.csv          <- file.path(pasture.params.dir, "lum_grass_classes.csv")
band.catalogue.csv           <- file.path(pasture.params.dir, "pasture_band_catalogue.csv")
