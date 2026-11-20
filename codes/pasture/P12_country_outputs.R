##### PASTURE P12: spatial exports (COG FLT4S + NAflag=-9999, GPKG, Parquet),
##### raster-to-table double-precision check, JSON sidecars, and atomic country RDS

library(terra)
library(sf)

## 1. Country summary (per species + totals + gamma_c + EW-MFA benchmark + KL prior adherence)
sp_summary <- alloc.sp[, .(
  LSU_alloc                  = sum(LSU),
  heads_alloc                = sum(heads),
  milk_t_alloc               = sum(milk_t),
  meat_t_alloc               = sum(meat_t),
  CH4_enteric_t              = sum(CH4_enteric_t),
  CH4_manure_mgt_t           = sum(CH4_manure_mgt_t),
  CH4_enteric_fao_t          = sum(CH4_enteric_fao_t),
  CH4_manure_mgt_fao_t       = sum(CH4_manure_mgt_fao_t),
  CH4_enteric_unfccc_t       = if (all(is.na(CH4_enteric_unfccc_t))) NA_real_ else sum(CH4_enteric_unfccc_t, na.rm = TRUE),
  CH4_manure_mgt_unfccc_t    = if (all(is.na(CH4_manure_mgt_unfccc_t))) NA_real_ else sum(CH4_manure_mgt_unfccc_t, na.rm = TRUE),
  N2O_manure_mgt_total_t     = sum(N2O_manure_mgt_total_t),
  N2O_pasture_prp_total_t    = sum(N2O_pasture_prp_total_t),
  N2O_manure_applied_total_t = sum(N2O_manure_applied_total_t),
  N_excreted_total_kg        = sum(N_excreted_total_kg),
  N_left_on_pasture_kg       = sum(N_left_on_pasture_kg),
  N_applied_soils_kg         = sum(N_applied_soils_kg),
  GHG_livestock_CO2e_t       = sum(GHG_livestock_CO2e_t)
), by = species]

sp_summary <- merge(
  sp_summary,
  curr.accounts[, .(species, heads_target = heads, lsu_target = lsu, milk_t_target = milk_t, meat_t_target = meat_t,
                    CH4_enteric_target_t = CH4_enteric_t, CH4_manure_mgt_target_t = CH4_manure_mgt_t)],
  by = "species", all.x = TRUE
)
sp_summary[, `:=`(region = lama.reg, year = curr.year)]

mfa_grazed <- if (nrow(curr.eurostat_mfa) > 0L) curr.eurostat_mfa$mfa_grazed_biomass_dm_t[1L] else NA_real_
mfa_fodder <- if (nrow(curr.eurostat_mfa) > 0L) curr.eurostat_mfa$mfa_fodder_crops_dm_t[1L] else NA_real_

direct_forage_dm <- sum(lum_summary[LUM.class %in% c(15:18, 23:25)]$forage_dm_t)
mown_forage_dm   <- sum(lum_summary[LUM.class %in% c(19:22)]$forage_dm_t)

country_meta_row <- data.table(
  region                     = lama.reg,
  country                    = country,
  year                       = curr.year,
  pasture_area_ha            = sum(cell_summary$area_ha),
  forage_dm_t                = sum(cell_summary$forage_dm_t),
  direct_pasture_forage_dm_t = direct_forage_dm,
  mown_grass_forage_dm_t     = mown_forage_dm,
  mean_YLDF_t_ha             = sum(cell_summary$forage_dm_t) / sum(cell_summary$area_ha),
  LSU_total                  = sum(cell_summary$LSU_total),
  grazing_feed_coef_t_dm_lsu = grazing_feed_coef_t_dm_lsu,
  direct_grazing_coef_t_lsu  = direct_forage_dm / sum(cell_summary$LSU_total),
  mfa_grazed_dm_t            = mfa_grazed,
  mfa_fodder_dm_t            = mfa_fodder,
  mfa_grazed_per_lsu         = if (!is.na(mfa_grazed)) mfa_grazed / sum(cell_summary$LSU_total) else NA_real_,
  CO2_SOC_t                  = sum(cell_summary$CO2_SOC_t),
  N2O_synth_fert_total_t     = sum(cell_summary$N2O_synth_fert_total_t),
  N2O_epic_raw_nfert_diag_t  = sum(lum_summary$N2O_epic_raw_nfert_diag_t),
  GHG_livestock_CO2e_t       = sum(cell_summary$GHG_livestock_CO2e_t),
  GHG_pasture_soil_CO2e_t    = sum(cell_summary$GHG_pasture_soil_CO2e_t),
  GHG_total_CO2e_t           = sum(cell_summary$GHG_total_CO2e_t),
  eurostat_lsk_prior_cov     = eurostat_lsk_cov_share,
  prior_kl_div               = if (exists("prior_kl_div", inherits = TRUE)) prior_kl_div else NA_real_,
  epic_imputed_area_share    = imp_share,
  ipf_stop_reason            = ipf_res$stop_reason,
  ipf_iterations             = ipf_res$iterations,
  gwp_version                = GWP_VERSION,
  lum_file                   = if (exists("curr.lum.source", inherits = TRUE)) curr.lum.source$basename else basename(LUM.file),
  unmanaged_grass_ha         = if (exists("curr.lum.source", inherits = TRUE)) curr.lum.source$unmanaged_grass_ha else NA_real_,
  heterogeneous_grass_ha     = if (exists("curr.lum.source", inherits = TRUE)) curr.lum.source$heterogeneous_grass_ha else NA_real_,
  leftover_grass_ha          = if (exists("curr.lum.source", inherits = TRUE)) curr.lum.source$leftover_grass_ha else NA_real_,
  raster_table_max_rel_diff  = NA_real_
)

nuts2_summary <- alloc.sp[, .(
  LSU                  = sum(LSU),
  heads                = sum(heads),
  milk_t               = sum(milk_t),
  meat_t               = sum(meat_t),
  GHG_livestock_CO2e_t = sum(GHG_livestock_CO2e_t)
), by = .(NUTS2, species)]
nuts2_summary[, `:=`(region = lama.reg, year = curr.year)]

band_cols <- band_catalogue[order(band_index)]$band_name
missing_bands <- setdiff(band_cols, names(cell_summary))
if (length(missing_bands) > 0L) {
  stop(sprintf("[P12] Raster band catalogue mismatch (%s %s): missing columns %s",
               lama.reg, curr.year, paste(missing_bands, collapse = ", ")))
}

## 2. Spatial exports (COG .tif FLT4S NA=-9999, GPKG, Parquet via arrow + JSON sidecars)
manifest_rel <- file.path("output", PASTURE_RESULT_TAG, "run_manifest.json")
out_band_cat <- file.path("output", PASTURE_RESULT_TAG, "pasture_band_catalogue.csv")
if (!file.exists(out_band_cat)) file.copy(band.catalogue.csv, out_band_cat, overwrite = TRUE)

if (isTRUE(EXPORT_PASTURE_SPATIAL)) {
  c_dir <- file.path("output", PASTURE_RESULT_TAG, "country_res")
  dir.create(c_dir, recursive = TRUE, showWarnings = FALSE)

  res   <- 1000
  xmin  <- min(cell_summary$EOFORIGIN)
  xmax  <- max(cell_summary$EOFORIGIN) + res
  ymin  <- min(cell_summary$NOFORIGIN)
  ymax  <- max(cell_summary$NOFORIGIN) + res
  ncols <- as.integer(round((xmax - xmin) / res))
  nrows <- as.integer(round((ymax - ymin) / res))

  tmpl <- terra::rast(
    nrows = nrows, ncols = ncols,
    xmin = xmin, xmax = xmax, ymin = ymin, ymax = ymax,
    crs = "EPSG:3035"
  )
  col_idx <- as.integer(round((cell_summary$EOFORIGIN - xmin) / res)) + 1L
  row_idx <- nrows - as.integer(round((cell_summary$NOFORIGIN - ymin) / res))
  cell_no <- terra::cellFromRowCol(tmpl, row_idx, col_idx)

  band_list <- lapply(band_cols, function(col) {
    r <- tmpl
    v <- rep(NA_real_, terra::ncell(tmpl))
    v[cell_no] <- cell_summary[[col]]
    terra::values(r) <- v
    r
  })
  r_stack <- terra::rast(band_list)
  names(r_stack) <- band_cols

  cog_path <- file.path(c_dir, sprintf("%s_pasture_%s_%s.tif", PASTURE_RESULT_TAG, lama.reg, curr.year))
  cog_tmp  <- paste0(cog_path, ".tmp.tif")
  terra::writeRaster(
    r_stack, cog_tmp,
    filetype = "COG",
    datatype = "FLT4S",
    NAflag   = -9999,
    gdal     = c("COMPRESS=DEFLATE", "PREDICTOR=2", "BLOCKSIZE=512",
                 "OVERVIEWS=AUTO", "OVERVIEW_RESAMPLING=AVERAGE"),
    overwrite = TRUE
  )
  if (!file.rename(cog_tmp, cog_path)) stop(sprintf("[P12] Atomic COG rename failed: %s", cog_path))

  ## Raster-to-table double-precision conservation check (spatial-downscaling.md Principle 8 item 6)
  r_chk <- terra::rast(cog_path)
  ext_bands <- band_catalogue[variable_type == "extensive"]$band_name
  rt_errs <- vapply(ext_bands, function(b) {
    v_ras <- sum(as.numeric(terra::values(r_chk[[b]], mat = FALSE)), na.rm = TRUE)
    v_tbl <- sum(as.numeric(cell_summary[[b]]), na.rm = TRUE)
    denom <- max(abs(v_tbl), 1e-6)
    abs(v_ras - v_tbl) / denom
  }, numeric(1))
  max_rt_err <- max(rt_errs, na.rm = TRUE)
  max_rt_band <- names(which.max(rt_errs))[1L]
  rm(r_chk)
  if (max_rt_err > 1e-4) {
    stop(sprintf("[P12] Raster-vs-table conservation check FAILED (%s %s) on band '%s': rel diff = %.4e > 1e-4",
                 lama.reg, curr.year, max_rt_band, max_rt_err))
  }
  country_meta_row[, raster_table_max_rel_diff := max_rt_err]
  curr.ledger[[length(curr.ledger) + 1L]] <- new_ledger_entry(
    "P12_raster_check", lama.reg, curr.year,
    paste0("cog_vs_table_", max_rt_band), "rel_diff",
    max_rt_err, 0,
    sprintf("All %d extensive FLT4S COG bands match cell_summary (max rel diff %.2e on %s)",
            length(ext_bands), max_rt_err, max_rt_band)
  )

  sp_meta_cog <- list(
    crs_epsg     = "EPSG:3035",
    grid_id_col  = "CELLCODE",
    resolution_m = c(1000, 1000),
    extent       = c(xmin, ymin, xmax, ymax),
    nrows        = nrows,
    ncols        = ncols,
    nodata       = -9999,
    datatype     = "FLT4S",
    layout       = "COG"
  )
  write_output_sidecar(
    data_path          = cog_path,
    product_name       = "ibiom_pasture_livestock_1km_cog",
    run_id             = PASTURE_RESULT_TAG,
    region             = lama.reg,
    year               = curr.year,
    spatial_meta       = sp_meta_cog,
    bands_df           = band_catalogue,
    legend_file        = out_band_cat,
    validation_summary = list(raster_table_max_rel_diff = max_rt_err, worst_band = max_rt_band, status = "PASS"),
    manifest_path      = manifest_rel
  )

  ## GPKG (1 km cell centroids in EPSG:3035, atomic temp -> rename + sidecar)
  gpkg_sf <- sf::st_as_sf(
    cell_summary[, c("CELLCODE", "EOFORIGIN", "NOFORIGIN", "SimUID", "NUTS2", band_cols), with = FALSE] %>%
      mutate(x_center = EOFORIGIN + 500, y_center = NOFORIGIN + 500),
    coords = c("x_center", "y_center"),
    crs = 3035
  )
  gpkg_path <- file.path(c_dir, sprintf("%s_pasture_%s_%s.gpkg", PASTURE_RESULT_TAG, lama.reg, curr.year))
  gpkg_tmp  <- paste0(gpkg_path, ".tmp.gpkg")
  sf::st_write(gpkg_sf, gpkg_tmp, delete_dsn = TRUE, quiet = TRUE)
  if (!file.rename(gpkg_tmp, gpkg_path)) stop(sprintf("[P12] Atomic GPKG rename failed: %s", gpkg_path))
  write_output_sidecar(
    data_path    = gpkg_path,
    product_name = "ibiom_pasture_livestock_1km_gpkg",
    run_id       = PASTURE_RESULT_TAG,
    region       = lama.reg,
    year         = curr.year,
    spatial_meta = list(crs_epsg = "EPSG:3035", grid_id_col = "CELLCODE", geometry = "Point (1 km centroid)", n_features = nrow(gpkg_sf)),
    bands_df     = band_catalogue,
    legend_file  = out_band_cat,
    manifest_path = manifest_rel
  )

  ## Canonical Tabular Parquet via arrow (atomic temp -> rename + sidecar)
  pq_path <- file.path(c_dir, sprintf("%s_pasture_%s_%s.parquet", PASTURE_RESULT_TAG, lama.reg, curr.year))
  save_parquet_atomic(cell_summary, pq_path)
  write_output_sidecar(
    data_path    = pq_path,
    product_name = "ibiom_pasture_livestock_1km_parquet",
    run_id       = PASTURE_RESULT_TAG,
    region       = lama.reg,
    year         = curr.year,
    spatial_meta = list(crs_epsg = "EPSG:3035", grid_id_col = "CELLCODE", n_rows = nrow(cell_summary)),
    bands_df     = band_catalogue,
    legend_file  = out_band_cat,
    manifest_path = manifest_rel
  )
}

## 3. Save atomic country RDS bundle (now includes raster_table_max_rel_diff in ledger & summary)
country_pkg <- list(
  run_id            = PASTURE_RESULT_TAG,
  region            = lama.reg,
  year              = curr.year,
  cell_summary      = cell_summary,
  lum_summary       = lum_summary,
  species_lum_alloc = alloc.sp,
  species_summary   = sp_summary,
  country_summary   = country_meta_row,
  nuts2_summary     = nuts2_summary,
  lum_source        = if (exists("curr.lum.source", inherits = TRUE)) curr.lum.source else list(file = LUM.file, basename = basename(LUM.file)),
  ledger            = rbindlist(curr.ledger),
  fallbacks         = if (length(curr.fallbacks) > 0L) rbindlist(curr.fallbacks) else data.table()
)
save_rds_atomic(country_pkg, res.file)
