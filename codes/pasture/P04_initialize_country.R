##### PASTURE P04: initialize country x year inputs and contracts

curr.year <- as.character(country_grid[JOB, "years"])
country   <- as.character(country_grid[JOB, "countries"])
lama.reg  <- as.character(country_grid[JOB, "lama.regs"])

LUM.file <- resolve_lum_raster(curr.year, lum_dir = LUM.path, input_dir = INPUT_DIR, must_exist = TRUE)
check_file_hydrated(LUM.file, check_magic = TRUE)

curr.lum.source <- list(
  file                  = LUM.file,
  basename              = basename(LUM.file),
  is_ibiom_explorer_cog = grepl("^ibiom_LUM_europe_100m_", basename(LUM.file))
)
message(sprintf("  [P04] LUM layer: %s", LUM.file))

curr.ledger    <- list()
curr.fallbacks <- list()

curr.grid <- grid_1km_all[NUTS0 == lama.reg]
if (nrow(curr.grid) == 0L) {
  stop(sprintf("[P04] No 1 km grid cells found for NUTS0='%s'.", lama.reg))
}

## Check for any border-imputed NUTS2 codes whose prefix != lama.reg
foreign_nuts2 <- curr.grid[substr(NUTS2, 1L, 2L) != lama.reg]
if (nrow(foreign_nuts2) > 0L) {
  curr.fallbacks[[length(curr.fallbacks) + 1L]] <- new_fallback_entry(
    stage = "P04_initialize", region = lama.reg, year = curr.year,
    kind = "border_nuts2_mismatch", requested = paste0(lama.reg, "*"),
    used = paste(unique(foreign_nuts2$NUTS2), collapse = ","),
    affected_share = nrow(foreign_nuts2) / nrow(curr.grid),
    reason = "1 km border cells carry neighboring imputed NUTS2 codes; priors fall back to national shares on these cells"
  )
}

curr.accounts <- faostat_accounts[region == lama.reg & year == curr.year]
assert_contract(
  curr.accounts, sprintf("P04/%s_%s/faostat_accounts", lama.reg, curr.year),
  req_cols = c("region", "year", "species", "heads", "lsu", "lsu_per_head",
               "milk_t", "meat_t", "CH4_enteric_t", "CH4_manure_mgt_t",
               "N2O_manure_mgt_total_t", "N2O_pasture_prp_total_t", "N2O_manure_applied_total_t"),
  key_cols = "species",
  non_neg_cols = c("heads", "lsu")
)
if (nrow(curr.accounts) != 4L) {
  stop(sprintf("[P04] Expected 4 ruminant species for %s %s, got %d.",
               lama.reg, curr.year, nrow(curr.accounts)))
}

curr.eurostat_lsk  <- eurostat_priors$nuts2_livestock[region == lama.reg & year == curr.year]
curr.eurostat_milk <- eurostat_priors$nuts2_milk[region == lama.reg & year == curr.year]
curr.eurostat_mfa  <- eurostat_priors$nat_mfa[region == lama.reg & year == curr.year]

message(sprintf("  [P04] %s (%s): %d grid cells, %.2f M LSU (FAOSTAT)",
                lama.reg, curr.year, nrow(curr.grid), sum(curr.accounts$lsu) / 1e6))
