##### USER CONFIGURATION — copy this file to user_config.R and edit #####
#### Do NOT commit user_config.R to Git — it is in .gitignore

## Data root directory (project-local "input", or point to a shared drive root)
INPUT_DIR        <- "input"
LUM_DIR          <- ""   # Optional override, else resolves /mnt/wdrv/iBIOM_Explorer/Land_use_and_management -> ~/accelerator/mnt/ibiom -> input/LUM_data
SHARED_INPUT_DIR <- "/mnt/wdrv/Data/preprocessed_data/iBIOM_CropMapping_input"

## GAMS installation path (only needed for script 15 and the GLOBIOM preparation scripts)
GAMS_PATH     <- "C:/GAMS/49"

## Run identifier (used to tag output files)
RESULT_TAG    <- "res_v1"

## Year(s) to process
RUN_YEARS     <- "2000"

## new FAO targets (FALSE) or old GLOBIOM targets (TRUE)
GLOBIOM_targets <- FALSE

#### Choose which LUM layer ID to distribute targets on
lum_crop_map  <- c(seq(2001,2005,1))

## Preparation steps to re-run even if their output exists (see codes/02_prepare_inputs.R),
## e.g. c("EPIC_vars", "GLOBIOM_old_crops")
FORCE_PREP    <- character()

## Skip countries whose result rds already exists in output/RESULT_TAG (resume an interrupted run)
SKIP_EXISTING <- FALSE

##### PASTURE & RUMINANT LIVESTOCK CONFIGURATION #############################

## Pasture run identifier, years ("2000", "2010", "2018"), and optional country subset
## Set PASTURE_COUNTRIES <- NULL for all EU-27 + UK countries, or e.g. c("AT", "NL", "ES")
PASTURE_RESULT_TAG     <- "pasture_v1"
PASTURE_RUN_YEARS      <- "2018"
PASTURE_COUNTRIES      <- NULL

## Grassland/pasture LUM classes to allocate (15:25 = managed/semi-natural; 26 = unmanaged)
lum_grass_map          <- 15:25

## Livestock statistics & GHG settings
LIVESTOCK_ACCOUNTING_SOURCE <- "faostat"    # FAOSTAT national accounts (QCL, GLE, EMN, EK)
FAOSTAT_EMISSION_SOURCE     <- "FAO TIER 1" # "FAO TIER 1" (complete) or "UNFCCC" (where available)
USE_EUROSTAT_PRIORS         <- TRUE         # Eurostat NUTS2 species shares (ef_lsk_*) & milk yield (agr_r_milkpr)
GWP_VERSION                 <- "AR6"        # "AR6" (CH4=27, N2O=273), "AR5" (28/265), or "AR4" (25/298)
EXPORT_PASTURE_SPATIAL      <- TRUE         # Export .gpkg, tabular .parquet (arrow), and COG .tif
