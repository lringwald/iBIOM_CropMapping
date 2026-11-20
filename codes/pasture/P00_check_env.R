##### PASTURE ENV CHECK: verify R version, packages, GDAL drivers, and project input paths
##### Run from repo root: Rscript codes/pasture/P00_check_env.R

required_pkgs <- c(
  "dplyr", "tidyr", "sf", "readr", "terra", "exactextractr",
  "countrycode", "data.table", "stringr", "ggplot2", "patchwork",
  "eurostat", "giscoR", "knitr", "markdown", "readxl", "scales", "arrow",
  "devtools", "nloptr", "matrixStats", "cli"
)

cat("=== R Environment Check ===\n")
cat("Working directory:", getwd(), "\n")
cat("R version        :", R.version.string, "\n")

pkg_status <- sapply(required_pkgs, requireNamespace, quietly = TRUE)
cat("\n=== Required Packages ===\n")
for (p in names(pkg_status)) {
  ver <- if (pkg_status[[p]]) as.character(utils::packageVersion(p)) else "MISSING"
  cat(sprintf("  %-15s : %s\n", p, ver))
}

missing_pkgs <- names(pkg_status)[!pkg_status]
if (length(missing_pkgs) > 0) {
  stop("Missing required R packages: ", paste(missing_pkgs, collapse = ", "))
}

cat("\n=== GDAL / Spatial Drivers ===\n")
v_drivers <- sf::st_drivers()$name
r_drivers <- terra::gdal(drivers = TRUE)
cat("  GPKG driver    :", "GPKG" %in% v_drivers, "\n")
cat("  Parquet driver :", "Parquet" %in% v_drivers, "(arrow fallback available:", pkg_status[["arrow"]], ")\n")
cat("  COG raster drv :", "COG" %in% r_drivers$name, "(GTiff:", "GTiff" %in% r_drivers$name, ")\n")

cat("\n=== Configuration & Project Input Paths ===\n")
if (!file.exists("user_config.R")) {
  stop("user_config.R not found. Copy user_config_TEMPLATE.R to user_config.R first.")
}
source("user_config.R")
source("codes/01_settings.R")

cat("  INPUT_DIR        :", INPUT_DIR, "\n")
cat("  LUM_DIR (path)   :", LUM.path, "\n")
cat("  SHARED_INPUT_DIR :", SHARED_INPUT_DIR, "\n")
cat("  PASTURE_TAG      :", PASTURE_RESULT_TAG, "\n")
cat("  PASTURE_YEARS    :", paste(PASTURE_RUN_YEARS, collapse = ", "), "\n")

source("codes/support/fun_pasture_contracts.R")

check_path <- function(label, path, required = TRUE) {
  ok <- !is.null(path) && nzchar(path) && (file.exists(path) || dir.exists(path))
  cat(sprintf("  %-26s : %s (%s)\n", label, ifelse(ok, "OK", if (required) "MISSING" else "OPTIONAL"), path))
  if (required && !ok) return(FALSE)
  TRUE
}

all_ok <- TRUE
has_shared_inputs <- nzchar(SHARED_INPUT_DIR) && dir.exists(SHARED_INPUT_DIR)
all_ok <- check_path("INPUT_DIR", INPUT_DIR, required = !has_shared_inputs) && all_ok
all_ok <- check_path("LUM.path", LUM.path, required = FALSE) && all_ok
for (yr in PASTURE_RUN_YEARS) {
  lum_resolved <- resolve_lum_raster(yr, lum_dir = LUM.path, input_dir = INPUT_DIR, must_exist = FALSE)
  ok_lum <- nzchar(lum_resolved) && check_path(paste0("LUM_", yr), lum_resolved, required = TRUE)
  if (ok_lum) {
    check_file_hydrated(lum_resolved, check_magic = TRUE)
    cat(sprintf("  %-26s : OK (BigTIFF/TIFF header verified)\n", paste0("LUM_", yr, " header")))
  }
  all_ok <- ok_lum && all_ok
}
need_raw_epic <- !(file.exists(EPIC.grass.pq.path) || file.exists(EPIC.grass.path))
all_ok <- check_path("EPIC grass Parquet", EPIC.grass.pq.path, required = FALSE) && all_ok
all_ok <- check_path("EPIC grass REF Parquet", EPIC.grass.ref.pq.path, required = FALSE) && all_ok
all_ok <- check_path("EPIC grass RDS", EPIC.grass.path, required = FALSE) && all_ok
all_ok <- check_path("EPIC Grassland YLDF", file.path(EPIC.grass.raw.path, "YLDF"), required = need_raw_epic) && all_ok
all_ok <- check_path("EPIC Grassland Ext", file.path(EPIC.grass.raw.path, "Externalities"), required = need_raw_epic) && all_ok
all_ok <- check_path("1km NUTS/SimU mapping", grid.1km.map.path, required = TRUE) && all_ok
all_ok <- check_path("FAOSTAT accounts RDS", faostat.accounts.path, required = FALSE) && all_ok
all_ok <- check_path("Eurostat priors RDS", eurostat.priors.path, required = FALSE) && all_ok
all_ok <- check_path("Pasture target dir", pasture.target.path, required = !(file.exists(faostat.accounts.path) && file.exists(eurostat.priors.path))) && all_ok

if (!all_ok) {
  stop("One or more required input paths were not found across INPUT_DIR, LUM_DIR, or SHARED_INPUT_DIR.")
}

cat("\n=== Cascade-Core IPF Engine ===\n")
eng <- ensure_cascade_engine()
cat("  fienberg() ok  :", exists("fienberg", where = asNamespace("cascadecore"), mode = "function"), "\n")

cat("\nEnvironment check PASSED.\n")
