##### PASTURE P07: join EPIC Grassland yield and soil/fertilizer parameters by SimUID x LUM.class

n_before <- nrow(temp.pasture)
temp.pasture <- merge(
  temp.pasture,
  EPIC_grass_params,
  by = c("SimUID", "LUM.class"),
  all.x = TRUE
)
if (nrow(temp.pasture) != n_before) {
  stop(sprintf("[P07] Cardinality violation joining EPIC_grass_params (%d -> %d rows).",
               n_before, nrow(temp.pasture)))
}

## Explicit imputation logging where SimUID x LUM.class has no EPIC simulation
temp.pasture[, epic_imputed := is.na(YLDF)]
n_imp <- sum(temp.pasture$epic_imputed)
imp_area_ha <- sum(temp.pasture$area_ha[temp.pasture$epic_imputed])
imp_share <- imp_area_ha / sum(temp.pasture$area_ha)

if (n_imp > 0L) {
  ## Tier 1 fallback: country area-weighted mean per LUM.class
  ctry_means <- temp.pasture[epic_imputed == FALSE, .(
    YLDF_c                  = stats::weighted.mean(YLDF, area_ha, na.rm = TRUE),
    OCPD_c                  = if (all(is.na(OCPD))) NA_real_ else stats::weighted.mean(OCPD, area_ha, na.rm = TRUE),
    dOCPD_c                 = stats::weighted.mean(dOCPD, area_ha, na.rm = TRUE),
    NFERT_c                 = stats::weighted.mean(NFERT, area_ha, na.rm = TRUE),
    FCO_c                   = stats::weighted.mean(FCO, area_ha, na.rm = TRUE),
    RSDC_c                  = stats::weighted.mean(RSDC, area_ha, na.rm = TRUE),
    NFERT_org_est_kg_ha_c   = stats::weighted.mean(NFERT_org_est_kg_ha, area_ha, na.rm = TRUE),
    NFERT_synth_est_kg_ha_c = stats::weighted.mean(NFERT_synth_est_kg_ha, area_ha, na.rm = TRUE),
    grazing_mode_c          = grazing_mode[1L]
  ), by = LUM.class]

  temp.pasture <- merge(temp.pasture, ctry_means, by = "LUM.class", all.x = TRUE)
  temp.pasture <- merge(temp.pasture, epic_eu_means, by = "LUM.class", all.x = TRUE)
  temp.pasture <- merge(temp.pasture, lum_grass_legend[, .(LUM.class, grazing_mode_leg = grazing_mode)], by = "LUM.class", all.x = TRUE)

  temp.pasture[epic_imputed == TRUE, `:=`(
    YLDF                  = fifelse(!is.na(YLDF_c), YLDF_c, YLDF_eu),
    OCPD                  = fifelse(!is.na(OCPD_c), OCPD_c, OCPD_eu),
    dOCPD                 = fifelse(!is.na(dOCPD_c), dOCPD_c, dOCPD_eu),
    NFERT                 = fifelse(!is.na(NFERT_c), NFERT_c, NFERT_eu),
    FCO                   = fifelse(!is.na(FCO_c), FCO_c, FCO_eu),
    RSDC                  = fifelse(!is.na(RSDC_c), RSDC_c, RSDC_eu),
    NFERT_org_est_kg_ha   = fifelse(!is.na(NFERT_org_est_kg_ha_c), NFERT_org_est_kg_ha_c, NFERT_org_est_kg_ha_eu),
    NFERT_synth_est_kg_ha = fifelse(!is.na(NFERT_synth_est_kg_ha_c), NFERT_synth_est_kg_ha_c, NFERT_synth_est_kg_ha_eu),
    grazing_mode          = fifelse(!is.na(grazing_mode_c), grazing_mode_c, grazing_mode_leg)
  )]

  drop_tmp <- grep("_(c|eu|leg)$", names(temp.pasture), value = TRUE)
  temp.pasture[, (drop_tmp) := NULL]

  curr.fallbacks[[length(curr.fallbacks) + 1L]] <- new_fallback_entry(
    stage = "P07_load_EPIC", region = lama.reg, year = curr.year,
    kind = "epic_missing_simuid",
    requested = "exact (SimUID, LUM.class) EPIC parameters",
    used = if (nrow(ctry_means) > 0L) "country_LUM_mean (with EU fallback)" else "EU_LUM_mean",
    affected_share = imp_share,
    reason = sprintf("%d of %d rows (%.1f ha) missing SimUID in EPIC Grassland tables", n_imp, n_before, imp_area_ha)
  )
}

temp.pasture[, forage_dm_t := area_ha * YLDF]

assert_contract(
  temp.pasture, sprintf("P07/%s_%s/temp.pasture", lama.reg, curr.year),
  req_cols = c("CELLCODE", "LUM.class", "area_ha", "YLDF", "forage_dm_t", "dOCPD", "NFERT_synth_est_kg_ha"),
  key_cols = c("CELLCODE", "LUM.class"),
  non_neg_cols = c("area_ha", "YLDF", "forage_dm_t", "NFERT_synth_est_kg_ha")
)

curr.ledger[[length(curr.ledger) + 1L]] <- new_ledger_entry(
  "P07_epic_grass", lama.reg, curr.year, "pasture_area_ha", "ha",
  sum(temp.pasture$area_ha), start_area_ha,
  sprintf("EPIC imputed area share = %.3f%%", 100 * imp_share)
)
curr.ledger[[length(curr.ledger) + 1L]] <- new_ledger_entry(
  "P07_epic_grass", lama.reg, curr.year, "forage_dm_t", "t DM",
  sum(temp.pasture$forage_dm_t), sum(temp.pasture$forage_dm_t),
  sprintf("Mean YLDF = %.2f t DM/ha", sum(temp.pasture$forage_dm_t) / sum(temp.pasture$area_ha))
)
message(sprintf("  [P07] Forage DM = %.0f t (mean %.2f t DM/ha; EPIC imputed %.2f%% area).",
                sum(temp.pasture$forage_dm_t),
                sum(temp.pasture$forage_dm_t) / sum(temp.pasture$area_ha),
                100 * imp_share))

