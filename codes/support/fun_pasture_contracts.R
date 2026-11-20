##### PASTURE PIPELINE CONTRACTS, HYDRATION GUARD, LEDGER, MANIFEST & 2D IPF
##### Adheres to .rules-hub/rules/data-pipelines.md, data-integrity.md, spatial-downscaling.md

#' Verify that a local or cloud-synced file is physically hydrated (not a 0-byte placeholder)
check_file_hydrated <- function(path, check_magic = TRUE) {
  if (is.null(path) || !nzchar(path) || !file.exists(path)) {
    stop(sprintf("[Hydration] Required file does not exist: %s", path))
  }
  info <- file.info(path)
  if (is.na(info$size) || info$size <= 0) {
    stop(sprintf("[Hydration] File has size 0 bytes (possible cloud placeholder): %s", path))
  }
  if (check_magic) {
    con <- file(path, "rb")
    on.exit(close(con), add = TRUE)
    hdr <- readBin(con, what = "raw", n = 4L)
    if (length(hdr) == 0L) {
      stop(sprintf("[Hydration] Could not read magic bytes (dehydrated/locked): %s", path))
    }
    ext <- tolower(tools::file_ext(path))
    if (ext %in% c("tif", "tiff")) {
      ok_tiff <- identical(hdr[1:4], as.raw(c(0x49, 0x49, 0x2a, 0x00))) ||
                 identical(hdr[1:4], as.raw(c(0x4d, 0x4d, 0x00, 0x2a))) ||
                 identical(hdr[1:4], as.raw(c(0x49, 0x49, 0x2b, 0x00))) ||
                 identical(hdr[1:4], as.raw(c(0x4d, 0x4d, 0x00, 0x2b)))
      if (!ok_tiff) stop(sprintf("[Hydration] Invalid GeoTIFF header bytes in %s", path))
    } else if (ext == "zip") {
      if (!identical(hdr[1:2], as.raw(c(0x50, 0x4b)))) {
        stop(sprintf("[Hydration] Invalid ZIP header bytes in %s", path))
      }
    } else if (ext == "parquet") {
      if (!identical(hdr[1:4], as.raw(c(0x50, 0x41, 0x52, 0x31)))) {
        stop(sprintf("[Hydration] Invalid Parquet header bytes (expected PAR1) in %s", path))
      }
      con_end <- file(path, "rb")
      on.exit(close(con_end), add = TRUE)
      seek(con_end, where = max(0, info$size - 4), origin = "start")
      ftr <- readBin(con_end, what = "raw", n = 4L)
      if (!identical(ftr[1:4], as.raw(c(0x50, 0x41, 0x52, 0x31)))) {
        stop(sprintf("[Hydration] Truncated Parquet footer bytes (expected PAR1) in %s", path))
      }
    } else if (ext == "rds") {
      ok_rds <- identical(hdr[1:2], as.raw(c(0x1f, 0x8b))) ||
                identical(hdr[1:4], as.raw(c(0xfd, 0x37, 0x7a, 0x58))) ||
                identical(hdr[1:3], as.raw(c(0x42, 0x5a, 0x68))) ||
                identical(hdr[1:2], as.raw(c(0x58, 0x0a))) ||
                identical(hdr[1:2], as.raw(c(0x41, 0x0a)))
      if (!ok_rds) {
        stop(sprintf("[Hydration] Invalid RDS header bytes in %s", path))
      }
    }
  }
  invisible(TRUE)
}

#' Assert explicit schema, unique keys, and non-negativity contracts at a stage boundary
assert_contract <- function(df, stage, req_cols = character(), key_cols = NULL,
                            non_neg_cols = character(), allow_empty = FALSE) {
  if (!is.data.frame(df)) {
    stop(sprintf("[%s] Contract FAILED: object is not a data.frame/data.table.", stage))
  }
  missing_cols <- setdiff(req_cols, names(df))
  if (length(missing_cols) > 0L) {
    stop(sprintf("[%s] Contract FAILED: missing required columns: %s",
                 stage, paste(missing_cols, collapse = ", ")))
  }
  if (!allow_empty && nrow(df) == 0L) {
    stop(sprintf("[%s] Contract FAILED: 0 rows returned.", stage))
  }
  dt <- data.table::as.data.table(df)
  if (!is.null(key_cols) && length(key_cols) > 0L) {
    na_keys <- vapply(key_cols, function(k) any(is.na(dt[[k]])), logical(1))
    if (any(na_keys)) {
      stop(sprintf("[%s] Contract FAILED: NA values in key columns: %s",
                   stage, paste(key_cols[na_keys], collapse = ", ")))
    }
    n_dup <- anyDuplicated(dt, by = key_cols)
    if (n_dup > 0L) {
      stop(sprintf("[%s] Contract FAILED: duplicate keys on (%s) at row %d.",
                   stage, paste(key_cols, collapse = ", "), n_dup))
    }
  }
  for (col in intersect(non_neg_cols, names(dt))) {
    vals <- dt[[col]]
    if (any(is.nan(vals) | is.infinite(vals), na.rm = TRUE)) {
      stop(sprintf("[%s] Contract FAILED: NaN/Inf detected in column '%s'.", stage, col))
    }
    if (any(vals < -1e-9, na.rm = TRUE)) {
      stop(sprintf("[%s] Contract FAILED: negative values (< -1e-9) in '%s' (min = %g).",
                   stage, col, min(vals, na.rm = TRUE)))
    }
  }
  invisible(TRUE)
}

#' Atomic write for RDS files (.tmp -> rename)
save_rds_atomic <- function(obj, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  saveRDS(obj, file = tmp)
  ok <- file.rename(tmp, path)
  if (!ok) stop(sprintf("Atomic rename failed: %s -> %s", tmp, path))
  invisible(path)
}

#' Atomic write for text/CSV/JSON lines
write_lines_atomic <- function(lines, path) {
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  writeLines(lines, tmp, useBytes = TRUE)
  ok <- file.rename(tmp, path)
  if (!ok) stop(sprintf("Atomic rename failed: %s -> %s", tmp, path))
  invisible(path)
}

#' Atomic write for Apache Parquet via arrow (.tmp -> rename)
save_parquet_atomic <- function(df, path) {
  if (!requireNamespace("arrow", quietly = TRUE)) {
    stop("[Parquet] Package 'arrow' is required to write canonical Parquet outputs.", call. = FALSE)
  }
  dir.create(dirname(path), recursive = TRUE, showWarnings = FALSE)
  tmp <- paste0(path, ".tmp")
  arrow::write_parquet(as.data.frame(df), tmp)
  ok <- file.rename(tmp, path)
  if (!ok) stop(sprintf("Atomic Parquet rename failed: %s -> %s", tmp, path))
  invisible(path)
}

#' Collect geospatial & R runtime versions (spatial-downscaling.md Principle 8 item 8)
ext_soft_versions <- function() {
  sf_ext <- tryCatch(as.list(sf::sf_extSoftVersion()), error = function(e) list())
  pkg_v <- function(p) if (requireNamespace(p, quietly = TRUE)) as.character(utils::packageVersion(p)) else NA_character_
  list(
    r_version = R.version.string,
    packages = list(
      terra      = pkg_v("terra"),
      sf         = pkg_v("sf"),
      data.table = pkg_v("data.table"),
      arrow      = pkg_v("arrow"),
      eurostat   = pkg_v("eurostat"),
      cascadecore = if (exists(".CASCADE_ENGINE", envir = .GlobalEnv)) get(".CASCADE_ENGINE", envir = .GlobalEnv)$version else pkg_v("cascadecore")
    ),
    system_libs = sf_ext
  )
}

#' Write schema-structured JSON sidecar (<file>.json) with all 9 Principle 8 groups
write_output_sidecar <- function(data_path,
                                 product_name,
                                 run_id,
                                 region = "EU",
                                 year = NA_character_,
                                 spatial_meta = NULL,
                                 bands_df = NULL,
                                 legend_file = NULL,
                                 validation_summary = NULL,
                                 manifest_path = NULL,
                                 config_list = NULL) {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    stop("[Sidecar] Package 'jsonlite' is required to write JSON sidecars.", call. = FALSE)
  }
  md5_val <- tryCatch(unname(tools::md5sum(data_path)[1]), error = function(e) NA_character_)
  leg_md5 <- if (!is.null(legend_file) && file.exists(legend_file)) unname(tools::md5sum(legend_file)[1]) else NA_character_
  git_cmd <- function(...) tryCatch(system2("git", c(...), stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_)

  sidecar <- list(
    identity = list(
      product_name = product_name,
      version      = run_id,
      file_name    = basename(data_path),
      file_md5     = md5_val,
      file_bytes   = file.info(data_path)$size,
      created_utc  = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC")
    ),
    content = list(
      scenario = run_id,
      region   = region,
      period   = as.character(year),
      bands    = if (!is.null(bands_df)) as.data.frame(bands_df) else NULL
    ),
    spatial = if (!is.null(spatial_meta)) spatial_meta else list(
      crs_epsg     = "EPSG:3035",
      grid_id_col  = "CELLCODE",
      nodata       = NULL
    ),
    legend = list(
      class_table_file = if (!is.null(legend_file)) basename(legend_file) else NULL,
      class_table_md5  = leg_md5
    ),
    lineage = list(
      run_id        = run_id,
      manifest_path = manifest_path,
      git_commit    = git_cmd("rev-parse", "HEAD"),
      git_branch    = git_cmd("rev-parse", "--abbrev-ref", "HEAD"),
      config        = config_list
    ),
    uncertainty = list(
      mode = "declared_point_estimate",
      note = "Deterministic 2D IPF allocation via cascadecore::fienberg() anchored to FAOSTAT EK/GLE/QCL/EMN accounts and Eurostat FSS NUTS2 spatial priors; spatial uncertainty layers are not sampled."
    ),
    validation = if (!is.null(validation_summary)) validation_summary else list(status = "see_run_report"),
    software = ext_soft_versions(),
    terms = list(
      license  = "IIASA / LAMASUS Project Internal & Research Use",
      citation = "iBIOM Pasture & Ruminant Livestock Disaggregation Pipeline (Non-GLOBIOM); LAMASUS 100 m LUM v1.0.0 (DOI: 10.5281/zenodo.21787459); FAOSTAT; Eurostat."
    )
  )
  out_json <- paste0(data_path, ".json")
  write_lines_atomic(jsonlite::toJSON(sidecar, auto_unbox = TRUE, pretty = TRUE, null = "null"), out_json)
  invisible(out_json)
}

#' Compute weighted KL divergence between post-IPF species shares a_mat and priors p_mat
#' (spatial-downscaling.md Verification Checklist: Prior Adherence D_r)
compute_kl_divergence <- function(a_mat, p_mat, weights) {
  a <- as.matrix(a_mat)
  p <- as.matrix(p_mat)
  w <- as.numeric(weights)
  valid <- is.finite(w) & w > 0 & rowSums(a, na.rm = TRUE) > 0
  if (!any(valid)) return(NA_real_)
  a <- a[valid, , drop = FALSE]
  p <- p[valid, , drop = FALSE]
  w <- w[valid]
  a <- sweep(pmax(a, 0), 1L, rowSums(pmax(a, 0)), "/")
  p <- pmax(p, 1e-12)
  p <- sweep(p, 1L, rowSums(p), "/")
  kl_row <- rowSums(ifelse(a > 0, a * log(a / p), 0))
  sum(w * kl_row) / sum(w)
}

#' Resolve a 100 m LUM GeoTIFF across WKUBE / accli / local roots for a given year
resolve_lum_raster <- function(year, lum_dir = NULL, input_dir = "input", must_exist = TRUE) {
  yr <- as.character(year)
  candidates <- character()

  env_lum <- Sys.getenv("LUM_DIR", "")
  roots <- unique(c(
    if (!is.null(lum_dir) && nzchar(lum_dir)) lum_dir else character(),
    if (nzchar(env_lum)) env_lum else character()
  ))
  for (rt in roots) {
    rt <- sub("/+$", "", rt)
    candidates <- c(
      candidates,
      file.path(rt, yr, sprintf("ibiom_LUM_europe_100m_%s.tif", yr)),
      file.path(rt, sprintf("ibiom_LUM_europe_100m_%s.tif", yr)),
      file.path(rt, yr, sprintf("LUM_fit_with_energy_levels_and_new_FM_%s.tif", yr)),
      file.path(rt, sprintf("LUM_%s.tif", yr))
    )
  }

  candidates <- c(
    candidates,
    sprintf("/mnt/wdrv/iBIOM_Explorer/Land_use_and_management/%s/ibiom_LUM_europe_100m_%s.tif", yr, yr),
    sprintf("/mnt/wdrv/Data/resulting_data/ibiom_LUM_europe_100m_%s", yr),
    path.expand(sprintf("~/accelerator/mnt/ibiom/iBIOM_Explorer/Land_use_and_management/%s/ibiom_LUM_europe_100m_%s.tif", yr, yr)),
    file.path(input_dir, "iBIOM_Explorer/Land_use_and_management", yr, sprintf("ibiom_LUM_europe_100m_%s.tif", yr)),
    file.path(input_dir, "LUM_data", yr, sprintf("ibiom_LUM_europe_100m_%s.tif", yr)),
    file.path(input_dir, "LUM_data", sprintf("ibiom_LUM_europe_100m_%s.tif", yr)),
    file.path(input_dir, "LUM_data", sprintf("LUM_%s.tif", yr))
  )
  candidates <- unique(candidates[nzchar(candidates)])

  for (cand in candidates) {
    if (file.exists(cand)) {
      sz <- file.info(cand)$size
      if (!is.na(sz) && sz > 0) return(cand)
    }
  }

  if (isTRUE(must_exist)) {
    stop(sprintf(
      "[LUM] Could not locate a hydrated LUM raster for year '%s'. Checked:\n  - %s",
      yr, paste(candidates, collapse = "\n  - ")
    ), call. = FALSE)
  }
  ""
}

#' Resolve an input file or directory across local input_dir, SHARED_INPUT_DIR, and accli mount
resolve_input_path <- function(rel_path,
                               input_dir = "input",
                               shared_input_dir = Sys.getenv("SHARED_INPUT_DIR", "/mnt/wdrv/Data/preprocessed_data/iBIOM_CropMapping_input")) {
  roots <- unique(c(
    if (!is.null(input_dir) && nzchar(input_dir)) input_dir else character(),
    if (!is.null(shared_input_dir) && nzchar(shared_input_dir)) shared_input_dir else character(),
    path.expand("~/accelerator/mnt/ibiom/Data/preprocessed_data/iBIOM_CropMapping_input")
  ))
  for (rt in roots) {
    cand <- file.path(rt, rel_path)
    if (dir.exists(cand)) return(cand)
    if (file.exists(cand)) {
      sz <- file.info(cand)$size
      if (!is.na(sz) && sz > 0) return(cand)
    }
  }
  file.path(input_dir, rel_path)
}

#' Build canonical 1 km EEA CELLCODE from EPSG:3035 origin coordinates
make_cellcode_1km <- function(eoforigin, noforigin) {
  sprintf("1kmE%dN%d", as.integer(round(eoforigin / 1000)), as.integer(round(noforigin / 1000)))
}

#' Deterministic file name resolver shared by producer and consumer (Principle 13.2)
pasture_country_rds_path <- function(result_tag, reg, year) {
  file.path("output", result_tag, sprintf("%s_%s_%s.rds", reg, year, result_tag))
}

pasture_country_fail_path <- function(result_tag, reg, year) {
  file.path("output", result_tag, sprintf("FAILED_%s_%s_%s.rds", reg, year, result_tag))
}

#' Conservation ledger append helper
new_ledger_entry <- function(stage, region, year, quantity, unit, value,
                             ref_value = NA_real_, note = "") {
  rel_diff <- if (!is.na(ref_value) && abs(ref_value) > 0) (value - ref_value) / abs(ref_value) else NA_real_
  data.frame(
    stage     = stage,
    region    = region,
    year      = as.character(year),
    quantity  = quantity,
    unit      = unit,
    value     = as.numeric(value),
    ref_value = as.numeric(ref_value),
    rel_diff  = as.numeric(rel_diff),
    note      = as.character(note),
    stringsAsFactors = FALSE
  )
}

#' Record an explicit fallback event for the run manifest (Principle 2 & 9)
new_fallback_entry <- function(stage, region, year, kind, requested, used,
                               affected_share = NA_real_, reason = "") {
  data.frame(
    stage          = stage,
    region         = region,
    year           = as.character(year),
    kind           = kind,
    requested      = as.character(requested),
    used           = as.character(used),
    affected_share = as.numeric(affected_share),
    reason         = as.character(reason),
    stringsAsFactors = FALSE
  )
}

#' Load the canonical cascade-core engine once per session and record provenance
#'
#' Resolves in strict order: `CASCADE_CORE_PATH` env var (checkout path or `"installed"`),
#' vendored submodule `external/cascade-core`, or sibling `../cascade-core`.
ensure_cascade_engine <- function(reload = FALSE) {
  if (!isTRUE(reload) && exists(".CASCADE_ENGINE", envir = .GlobalEnv)) {
    return(invisible(get(".CASCADE_ENGINE", envir = .GlobalEnv)))
  }

  env_path <- Sys.getenv("CASCADE_CORE_PATH", "")
  if (nzchar(env_path)) {
    path   <- env_path
    source <- "CASCADE_CORE_PATH"
  } else if (file.exists(file.path("external", "cascade-core", "DESCRIPTION"))) {
    path   <- file.path("external", "cascade-core")
    source <- "vendored external/cascade-core"
  } else if (file.exists(file.path("..", "cascade-core", "DESCRIPTION"))) {
    path   <- file.path("..", "cascade-core")
    source <- "sibling ../cascade-core"
  } else if (requireNamespace("cascadecore", quietly = TRUE)) {
    path   <- "installed"
    source <- "installed package"
  } else {
    stop(
      "[cascade-core] Engine not found at external/cascade-core, ../cascade-core, or installed library. ",
      "Initialize external/cascade-core or set CASCADE_CORE_PATH.",
      call. = FALSE
    )
  }

  git_info <- function(dir) {
    if (!nzchar(Sys.which("git")) || !dir.exists(dir)) {
      return(list(commit = NA_character_, branch = NA_character_, dirty = NA))
    }
    g <- function(...) {
      out <- suppressWarnings(system2("git", c("-C", dir, ...), stdout = TRUE, stderr = FALSE))
      if (!is.null(attr(out, "status")) && attr(out, "status") != 0) character() else out
    }
    commit <- g("rev-parse", "HEAD")
    if (!length(commit)) return(list(commit = NA_character_, branch = NA_character_, dirty = NA))
    list(
      commit = commit[1L],
      branch = paste(g("rev-parse", "--abbrev-ref", "HEAD"), collapse = ""),
      dirty  = length(g("status", "--porcelain", "--untracked-files=no")) > 0L
    )
  }

  pinned <- NA_character_
  if (nzchar(Sys.which("git"))) {
    pin_out <- suppressWarnings(system2("git", c("ls-tree", "HEAD", "external/cascade-core"), stdout = TRUE, stderr = FALSE))
    hit <- grep("^160000 commit", pin_out, value = TRUE)
    if (length(hit)) pinned <- sub("^160000 commit ([0-9a-f]+)\t.*$", "\\1", hit[1L])
  }

  if (identical(path, "installed")) {
    suppressMessages(library(cascadecore))
    info <- list(
      path    = "installed",
      source  = source,
      version = as.character(utils::packageVersion("cascadecore")),
      commit  = NA_character_,
      branch  = NA_character_,
      dirty   = NA
    )
  } else {
    if (!file.exists(file.path(path, "DESCRIPTION"))) {
      stop(sprintf("[cascade-core] '%s' is not an R package checkout.", path), call. = FALSE)
    }
    if (!requireNamespace("devtools", quietly = TRUE)) {
      stop("[cascade-core] 'devtools' package is required to load ", path, call. = FALSE)
    }
    suppressMessages(devtools::load_all(path, quiet = TRUE))
    desc <- read.dcf(file.path(path, "DESCRIPTION"), fields = "Version")
    info <- c(
      list(
        path    = normalizePath(path, winslash = "/"),
        source  = source,
        version = unname(desc[1L, "Version"])
      ),
      git_info(path)
    )
  }

  if (!exists("fienberg", where = asNamespace("cascadecore"), mode = "function")) {
    stop("[cascade-core] Loaded cascadecore namespace does not expose fienberg().", call. = FALSE)
  }

  info$pinned_commit <- pinned
  info$matches_pin <- !is.na(info$commit) && !is.na(pinned) && identical(info$commit, pinned)
  assign(".CASCADE_ENGINE", info, envir = .GlobalEnv)
  message(sprintf(
    "  [cascade-core] Loaded cascadecore v%s (%s: %s, commit %s%s)",
    info$version, info$source, info$path,
    if (is.na(info$commit)) "untracked/vendored" else substr(info$commit, 1L, 7L),
    if (isTRUE(info$dirty)) ", uncommitted changes" else ""
  ))
  invisible(info)
}

#' 2D Iterative Proportional Fitting strictly via cascadecore::fienberg()
#'
#' Allocates a non-negative matrix X (n_units x n_species) from prior share matrix
#' `seed_mat` so that rowSums(X) == row_targets and colSums(X) == col_targets.
#' Applies MIN_EXP = 1e-12 strictly to active cells before delegating rebalancing
#' to `cascadecore::fienberg()`.
solve_ipf_2d <- function(seed_mat, row_targets, col_targets,
                         rel_tol = 1e-9, abs_tol = 1e-12, max_iter = 500L) {
  MIN_EXP <- 1e-12
  ensure_cascade_engine()

  nr <- nrow(seed_mat)
  nc <- ncol(seed_mat)
  if (length(row_targets) != nr || length(col_targets) != nc) {
    stop("[IPF] Dimension mismatch between seed_mat and targets.")
  }
  row_targets <- as.numeric(row_targets)
  col_targets <- as.numeric(col_targets)
  tot_r <- sum(row_targets)
  tot_c <- sum(col_targets)
  if (tot_r <= 0 || tot_c <= 0) {
    stop("[IPF] Non-positive total row or column target.")
  }
  if (abs(tot_r - tot_c) > max(1e-6 * max(tot_r, tot_c), 1e-6)) {
    stop(sprintf("[IPF] Infeasible marginal totals: sum(row)=%.6f vs sum(col)=%.6f", tot_r, tot_c))
  }

  S0 <- matrix(as.numeric(seed_mat), nrow = nr, ncol = nc)
  S0[is.na(S0) | S0 < 0] <- 0

  active_rows <- row_targets > 0
  active_cols <- col_targets > 0
  S0[!active_rows, ] <- 0
  S0[, !active_cols] <- 0

  ## Apply strict positive floor MIN_EXP on active cells so disconnected sub-blocks remain feasible
  active_mask <- outer(active_rows, active_cols, "&")
  S0[active_mask] <- pmax(S0[active_mask], MIN_EXP)

  ## Row-normalize active rows to satisfy cascadecore::fienberg() stochastic-row contract
  rs <- rowSums(S0)
  S0[active_rows, ] <- sweep(S0[active_rows, , drop = FALSE], 1L, rs[active_rows], "/")

  f_res <- cascadecore::fienberg(
    start_mat   = S0,
    target_from = row_targets,
    target_to   = col_targets,
    max.iter    = as.integer(max_iter),
    tol.optim   = abs_tol,
    tol.gain    = 1e-14,
    min.iter    = 1L,
    tol.margin  = rel_tol
  )

  X <- sweep(f_res$adjusted_matrix, 1L, row_targets, `*`)
  X[!active_rows, ] <- 0
  X[, !active_cols] <- 0
  if (!is.null(colnames(seed_mat))) colnames(X) <- colnames(seed_mat)

  final_row_rel <- max(abs(rowSums(X) - row_targets) / pmax(row_targets, 1e-12))
  final_col_rel <- max(abs(colSums(X) - col_targets) / pmax(col_targets, 1e-12))
  final_row_abs <- max(abs(rowSums(X) - row_targets))
  final_col_abs <- max(abs(colSums(X) - col_targets))

  stop_label <- if (isTRUE(f_res$converged)) {
    "converged (cascadecore::fienberg)"
  } else {
    paste0("cascadecore::fienberg: ", f_res$stop.reason)
  }

  if (final_row_rel > 1e-4 && final_row_abs > 1e-4) {
    stop(sprintf("[IPF] Row convergence FAILED (max rel=%.3e, abs=%.3e, reason=%s)",
                 final_row_rel, final_row_abs, stop_label))
  }
  if (final_col_rel > 1e-4 && final_col_abs > 1e-4) {
    stop(sprintf("[IPF] Col convergence FAILED (max rel=%.3e, abs=%.3e, reason=%s)",
                 final_col_rel, final_col_abs, stop_label))
  }

  list(
    alloc                = X,
    stop_reason          = stop_label,
    iterations           = as.integer(f_res$iter),
    converged            = isTRUE(f_res$converged),
    margin_error         = as.numeric(f_res$margin_error),
    fienberg_stop_reason = as.character(f_res$stop.reason),
    max_row_rel          = final_row_rel,
    max_col_rel          = final_col_rel,
    max_row_abs          = final_row_abs,
    max_col_abs          = final_col_abs,
    engine               = "cascadecore::fienberg"
  )
}

#' Load reference constants CSV as named numeric list
load_pasture_constants <- function(path) {
  check_file_hydrated(path, check_magic = FALSE)
  df <- utils::read.csv(path, stringsAsFactors = FALSE)
  setNames(as.numeric(df$value), df$param)
}

#' Resolve GWP100 pair for CH4 and N2O from GWP_VERSION
resolve_gwp <- function(gwp_version, consts) {
  switch(
    toupper(gwp_version),
    "AR6" = c(CH4 = consts[["GWP_CH4_AR6"]], N2O = consts[["GWP_N2O_AR6"]]),
    "AR5" = c(CH4 = consts[["GWP_CH4_AR5"]], N2O = consts[["GWP_N2O_AR5"]]),
    "AR4" = c(CH4 = consts[["GWP_CH4_AR4"]], N2O = consts[["GWP_N2O_AR4"]]),
    stop(sprintf("Unsupported GWP_VERSION '%s'; allowed: AR6, AR5, AR4.", gwp_version))
  )
}

