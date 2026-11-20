# =============================================================================
# init.R — Single dependency contract for iBIOM CropMapping & Pasture WKUBE
# =============================================================================
message(">>> [init.R] checking iBIOM CropMapping & Pasture dependencies")

.repos <- getOption("repos")
.configured <- !is.null(.repos) && "CRAN" %in% names(.repos) &&
               nzchar(.repos[["CRAN"]]) && !identical(unname(.repos[["CRAN"]]), "@CRAN@")
if (!.configured) {
  .code <- tryCatch({
    if (!file.exists("/etc/os-release")) stop("not linux")
    os <- readLines("/etc/os-release", warn = FALSE)
    gsub('"', "", sub("^VERSION_CODENAME=", "", grep("^VERSION_CODENAME=", os, value = TRUE)[1]))
  }, error = function(e) NA_character_)
  options(repos = if (!is.na(.code) && nzchar(.code) && .Platform$OS.type == "unix")
            c(CRAN = sprintf("https://packagemanager.posit.co/cran/__linux__/%s/latest", .code))
          else c(CRAN = "https://cloud.r-project.org/"))
}

CRAN_PKGS <- c(
  "data.table", "dplyr", "tidyr", "sf", "terra", "exactextractr",
  "arrow", "readxl", "readr", "stringr", "countrycode",
  "ggplot2", "patchwork", "scales", "knitr", "markdown",
  "jsonlite", "yaml", "eurostat", "giscoR", "nloptr", "matrixStats", "cli",
  "devtools", "remotes"
)

miss <- CRAN_PKGS[!vapply(CRAN_PKGS, requireNamespace, logical(1), quietly = TRUE)]
if (length(miss)) {
  message(">>> installing CRAN packages: ", paste(miss, collapse = ", "))
  install.packages(miss)
}

if (!requireNamespace("downscalr", quietly = TRUE)) {
  message(">>> installing tkrisztin/downscalr from GitHub...")
  remotes::install_github("tkrisztin/downscalr@2d38f3fb78244b3c6a466ace2600ca70c396c37e", upgrade = "never")
}

if (file.exists("external/cascade-core/DESCRIPTION") && !requireNamespace("cascadecore", quietly = TRUE)) {
  message(">>> installing vendored external/cascade-core...")
  remotes::install_local("external/cascade-core", upgrade = "never")
}

ALL_PKGS <- c(CRAN_PKGS, "downscalr")
if (file.exists("external/cascade-core/DESCRIPTION") || requireNamespace("cascadecore", quietly = TRUE)) {
  ALL_PKGS <- c(ALL_PKGS, "cascadecore")
}

ok <- vapply(ALL_PKGS, requireNamespace, logical(1), quietly = TRUE)
for (p in ALL_PKGS) message(sprintf("    %-15s %s", p, if (ok[[p]]) "ok" else "MISSING"))
message("    ", R.version.string)
if (!all(ok)) stop("dependencies missing: ", paste(ALL_PKGS[!ok], collapse = ", "))
message(">>> [init.R] all dependencies ok")

