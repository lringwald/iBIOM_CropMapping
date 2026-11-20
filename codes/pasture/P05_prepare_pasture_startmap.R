##### PASTURE P05: prepare pasture/grassland start areas from 100 m LUM raster on 1 km EEA grid

library(terra)
library(data.table)

LUM.rast <- terra::rast(LUM.file)
country_ext <- terra::ext(
  min(curr.grid$EOFORIGIN) - 1000,
  max(curr.grid$EOFORIGIN) + 2000,
  min(curr.grid$NOFORIGIN) - 1000,
  max(curr.grid$NOFORIGIN) + 2000
)
LUM.crop <- terra::crop(LUM.rast, country_ext)

lum_vals <- terra::values(LUM.crop, mat = FALSE)
lum_xy   <- terra::xyFromCell(LUM.crop, seq_len(terra::ncell(LUM.crop)))

aux_idx <- which(!is.na(lum_vals) & lum_vals %in% c(26L, 4012L, 4013L, 40000L))
unmanaged_grass_ha     <- 0
heterogeneous_grass_ha <- 0
leftover_grass_ha      <- 0
if (length(aux_idx) > 0L) {
  aux_dt <- data.table(
    EOFORIGIN = floor(lum_xy[aux_idx, 1] / 1000) * 1000,
    NOFORIGIN = floor(lum_xy[aux_idx, 2] / 1000) * 1000,
    LUM.class = as.integer(lum_vals[aux_idx])
  )[curr.grid[, .(EOFORIGIN, NOFORIGIN)], on = .(EOFORIGIN, NOFORIGIN), nomatch = 0L]
  unmanaged_grass_ha     <- as.numeric(aux_dt[LUM.class == 26L, .N])
  heterogeneous_grass_ha <- as.numeric(aux_dt[LUM.class %in% c(4012L, 4013L), .N])
  leftover_grass_ha      <- as.numeric(aux_dt[LUM.class == 40000L, .N])
  rm(aux_dt)
}
rm(aux_idx)

if (exists("curr.lum.source", inherits = TRUE)) {
  curr.lum.source$unmanaged_grass_ha     <- unmanaged_grass_ha
  curr.lum.source$heterogeneous_grass_ha <- heterogeneous_grass_ha
  curr.lum.source$leftover_grass_ha      <- leftover_grass_ha
}

keep_idx <- which(!is.na(lum_vals) & lum_vals %in% lum_grass_map)
if (length(keep_idx) == 0L) {
  stop(sprintf("[P05] Zero 100 m grassland pixels found for %s %s in LUM classes (%s).",
               lama.reg, curr.year, paste(lum_grass_map, collapse = ",")))
}

lum_dt <- data.table(
  EOFORIGIN = floor(lum_xy[keep_idx, 1] / 1000) * 1000,
  NOFORIGIN = floor(lum_xy[keep_idx, 2] / 1000) * 1000,
  LUM.class = as.integer(lum_vals[keep_idx])
)
rm(LUM.rast, LUM.crop, lum_vals, lum_xy, keep_idx)

## Assign each 100 m pixel (1 ha = 0.01 km^2) to its 1 km EEA CELLCODE
lum_dt <- lum_dt[
  curr.grid[, .(CELLCODE, EOFORIGIN, NOFORIGIN, SimUID, NUTS2)],
  on = .(EOFORIGIN, NOFORIGIN),
  nomatch = 0L
]

temp.pasture <- lum_dt[, .(
  area_ha  = as.numeric(.N),
  area_km2 = .N * 0.01
), by = .(CELLCODE, EOFORIGIN, NOFORIGIN, SimUID, NUTS2, LUM.class)]
rm(lum_dt)

assert_contract(
  temp.pasture, sprintf("P05/%s_%s/temp.pasture", lama.reg, curr.year),
  req_cols = c("CELLCODE", "EOFORIGIN", "NOFORIGIN", "SimUID", "NUTS2", "LUM.class", "area_ha", "area_km2"),
  key_cols = c("CELLCODE", "LUM.class"),
  non_neg_cols = c("area_ha", "area_km2")
)
if (any(temp.pasture[, .(tot = sum(area_ha)), by = CELLCODE]$tot > 100 + 1e-6)) {
  stop(sprintf("[P05] Cell pasture area exceeds 100 ha physical capacity in %s.", lama.reg))
}

start_area_ha  <- sum(temp.pasture$area_ha)
start_area_km2 <- sum(temp.pasture$area_km2)
curr.ledger[[length(curr.ledger) + 1L]] <- new_ledger_entry(
  "P05_startmap", lama.reg, curr.year, "pasture_area_ha", "ha",
  start_area_ha, start_area_ha,
  sprintf("LUM classes %s (%d cells); excluded aux ha: G12_26=%.0f, C1C2_4012_4013=%.0f, leftover_40000=%.0f; file=%s",
          paste(range(lum_grass_map), collapse = "-"), uniqueN(temp.pasture$CELLCODE),
          unmanaged_grass_ha, heterogeneous_grass_ha, leftover_grass_ha, basename(LUM.file))
)
message(sprintf("  [P05] Start map: %.1f ha (%.2f km^2) across %d cells x LUM rows.",
                start_area_ha, start_area_km2, nrow(temp.pasture)))

