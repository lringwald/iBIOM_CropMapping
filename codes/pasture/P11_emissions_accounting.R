##### PASTURE P11: full livestock & pasture GHG emissions + N excretion accounting
##### - Livestock emissions & N flows per head from FAOSTAT GLE + EMN
##### - Land-level pasture SOC CO2 (-dOCPD) and synthetic N2O kept strictly at
#####   (CELLCODE, LUM.class) level so land totals are NEVER multiplied by 4 species!

coef_cols <- c(
  "species",
  "CH4_enteric_t_head", "CH4_manure_mgt_t_head",
  "N2O_manure_mgt_dir_t_head", "N2O_manure_mgt_ind_t_head",
  "N2O_pasture_prp_dir_t_head", "N2O_pasture_prp_ind_t_head",
  "N2O_manure_apl_dir_t_head", "N2O_manure_apl_ind_t_head",
  "N_excreted_kg_head", "N_left_on_pasture_kg_head",
  "N_treated_mms_kg_head", "N_applied_soils_kg_head",
  "CH4_enteric_unfccc_t_head", "CH4_manure_mgt_unfccc_t_head",
  "N2O_manure_mgt_dir_unfccc_t_head"
)
alloc.sp <- merge(alloc.sp, curr.accounts[, ..coef_cols], by = "species", all.x = TRUE)

use_unfccc <- identical(toupper(FAOSTAT_EMISSION_SOURCE), "UNFCCC")
if (use_unfccc) {
  n_miss_u <- sum(is.na(curr.accounts$CH4_enteric_unfccc_t_head))
  if (n_miss_u > 0L) {
    curr.fallbacks[[length(curr.fallbacks) + 1L]] <- new_fallback_entry(
      stage = "P11_emissions", region = lama.reg, year = curr.year,
      kind = "unfccc_missing_species", requested = "UNFCCC GLE", used = "FAO TIER 1 fallback",
      affected_share = n_miss_u / nrow(curr.accounts),
      reason = "Species absent in FAOSTAT GLE UNFCCC rows"
    )
  }
}

alloc.sp[, `:=`(
  CH4_enteric_fao_t         = heads * fifelse(is.na(CH4_enteric_t_head), 0, CH4_enteric_t_head),
  CH4_manure_mgt_fao_t      = heads * fifelse(is.na(CH4_manure_mgt_t_head), 0, CH4_manure_mgt_t_head),
  CH4_enteric_unfccc_t      = heads * CH4_enteric_unfccc_t_head,
  CH4_manure_mgt_unfccc_t   = heads * CH4_manure_mgt_unfccc_t_head,
  N2O_manure_mgt_dir_unfccc_t = heads * N2O_manure_mgt_dir_unfccc_t_head,

  CH4_enteric_t = heads * fifelse(
    rep(use_unfccc, .N) & !is.na(CH4_enteric_unfccc_t_head),
    CH4_enteric_unfccc_t_head,
    fifelse(is.na(CH4_enteric_t_head), 0, CH4_enteric_t_head)
  ),
  CH4_manure_mgt_t = heads * fifelse(
    rep(use_unfccc, .N) & !is.na(CH4_manure_mgt_unfccc_t_head),
    CH4_manure_mgt_unfccc_t_head,
    fifelse(is.na(CH4_manure_mgt_t_head), 0, CH4_manure_mgt_t_head)
  ),
  N2O_manure_mgt_direct_t = heads * fifelse(
    rep(use_unfccc, .N) & !is.na(N2O_manure_mgt_dir_unfccc_t_head),
    N2O_manure_mgt_dir_unfccc_t_head,
    fifelse(is.na(N2O_manure_mgt_dir_t_head), 0, N2O_manure_mgt_dir_t_head)
  ),
  N2O_manure_mgt_indirect_t   = heads * fifelse(is.na(N2O_manure_mgt_ind_t_head), 0, N2O_manure_mgt_ind_t_head),
  N2O_pasture_prp_direct_t    = heads * fifelse(is.na(N2O_pasture_prp_dir_t_head), 0, N2O_pasture_prp_dir_t_head),
  N2O_pasture_prp_indirect_t  = heads * fifelse(is.na(N2O_pasture_prp_ind_t_head), 0, N2O_pasture_prp_ind_t_head),
  N2O_manure_applied_direct_t = heads * fifelse(is.na(N2O_manure_apl_dir_t_head), 0, N2O_manure_apl_dir_t_head),
  N2O_manure_applied_indirect_t = heads * fifelse(is.na(N2O_manure_apl_ind_t_head), 0, N2O_manure_apl_ind_t_head),
  N_excreted_total_kg         = heads * fifelse(is.na(N_excreted_kg_head), 0, N_excreted_kg_head),
  N_left_on_pasture_kg        = heads * fifelse(is.na(N_left_on_pasture_kg_head), 0, N_left_on_pasture_kg_head),
  N_treated_mms_kg            = heads * fifelse(is.na(N_treated_mms_kg_head), 0, N_treated_mms_kg_head),
  N_applied_soils_kg          = heads * fifelse(is.na(N_applied_soils_kg_head), 0, N_applied_soils_kg_head)
)]

alloc.sp[, `:=`(
  N2O_manure_mgt_total_t     = N2O_manure_mgt_direct_t + N2O_manure_mgt_indirect_t,
  N2O_pasture_prp_total_t    = N2O_pasture_prp_direct_t + N2O_pasture_prp_indirect_t,
  N2O_manure_applied_total_t = N2O_manure_applied_direct_t + N2O_manure_applied_indirect_t
)]
alloc.sp[, `:=`(
  GHG_livestock_CO2e_t = gwp_pair[["CH4"]] * (CH4_enteric_t + CH4_manure_mgt_t) +
    gwp_pair[["N2O"]] * (N2O_manure_mgt_total_t + N2O_pasture_prp_total_t + N2O_manure_applied_total_t)
)]

drop_coefs <- setdiff(coef_cols, "species")
alloc.sp[, (drop_coefs) := NULL]

## Land/soil emissions computed strictly once per (CELLCODE, LUM.class)
c_co2   <- pasture_constants[["C_to_CO2"]]
n_n2o   <- pasture_constants[["N2O_N_to_N2O"]]
ef1     <- pasture_constants[["EF1_synth_ipcc2019"]]
f_gasf  <- pasture_constants[["Frac_GASF_ipcc2019"]]
ef4     <- pasture_constants[["EF4_volat_ipcc2019"]]
f_leach <- pasture_constants[["Frac_LEACH_ipcc2019"]]
ef5     <- pasture_constants[["EF5_leach_ipcc2019"]]
ind_f   <- f_gasf * ef4 + f_leach * ef5

temp.pasture[, `:=`(
  CO2_SOC_t                 = -dOCPD * area_ha * c_co2,
  N_synth_applied_kg        = NFERT_synth_est_kg_ha * area_ha,
  N2O_synth_fert_direct_t   = (NFERT_synth_est_kg_ha * area_ha / 1000) * ef1 * n_n2o,
  N2O_synth_fert_indirect_t = (NFERT_synth_est_kg_ha * area_ha / 1000) * ind_f * n_n2o,
  N2O_epic_raw_nfert_diag_t = (NFERT * area_ha / 1000) * (ef1 + ind_f) * n_n2o
)]
temp.pasture[, `:=`(
  N2O_synth_fert_total_t  = N2O_synth_fert_direct_t + N2O_synth_fert_indirect_t,
  GHG_pasture_soil_CO2e_t = CO2_SOC_t + gwp_pair[["N2O"]] * (N2O_synth_fert_direct_t + N2O_synth_fert_indirect_t)
)]

## Aggregate species-level allocation to (CELLCODE, LUM.class), then join 1:1 with land-level temp.pasture
lsk_lum <- alloc.sp[, .(
  LSU_allocated              = sum(LSU),
  heads_total                = sum(heads),
  milk_t                     = sum(milk_t),
  meat_t                     = sum(meat_t),
  CH4_enteric_t              = sum(CH4_enteric_t),
  CH4_manure_mgt_t           = sum(CH4_manure_mgt_t),
  N2O_manure_mgt_total_t     = sum(N2O_manure_mgt_total_t),
  N2O_pasture_prp_total_t    = sum(N2O_pasture_prp_total_t),
  N2O_manure_applied_total_t = sum(N2O_manure_applied_total_t),
  N_excreted_total_kg        = sum(N_excreted_total_kg),
  N_left_on_pasture_kg       = sum(N_left_on_pasture_kg),
  N_applied_soils_kg         = sum(N_applied_soils_kg),
  GHG_livestock_CO2e_t       = sum(GHG_livestock_CO2e_t)
), by = .(CELLCODE, LUM.class)]

sp_wide <- dcast(alloc.sp, CELLCODE + LUM.class ~ species, value.var = c("heads", "LSU"), fill = 0)
setnames(sp_wide,
         c("heads_dairy_cattle", "heads_non_dairy_cattle", "heads_sheep", "heads_goats",
           "LSU_dairy_cattle", "LSU_non_dairy_cattle", "LSU_sheep", "LSU_goats"),
         c("dairy_cattle_heads", "non_dairy_cattle_heads", "sheep_heads", "goats_heads",
           "dairy_cattle_lsu", "non_dairy_cattle_lsu", "sheep_lsu", "goats_lsu"))

lum_summary <- merge(temp.pasture, lsk_lum, by = c("CELLCODE", "LUM.class"), all.x = TRUE)
lum_summary <- merge(lum_summary, sp_wide, by = c("CELLCODE", "LUM.class"), all.x = TRUE)
if (nrow(lum_summary) != nrow(temp.pasture)) {
  stop(sprintf("[P11] 1:1 join cardinality failed on lum_summary (%d vs %d).",
               nrow(lum_summary), nrow(temp.pasture)))
}

lum_summary[, GHG_total_CO2e_t := GHG_livestock_CO2e_t + GHG_pasture_soil_CO2e_t]
assert_contract(
  lum_summary, sprintf("P11/%s_%s/lum_summary", lama.reg, curr.year),
  req_cols = c("CELLCODE", "LUM.class", "area_ha", "forage_dm_t", "LSU_allocated",
               "CO2_SOC_t", "N2O_synth_fert_total_t", "GHG_livestock_CO2e_t", "GHG_pasture_soil_CO2e_t", "GHG_total_CO2e_t"),
  key_cols = c("CELLCODE", "LUM.class"),
  non_neg_cols = c("area_ha", "forage_dm_t", "LSU_allocated", "N2O_synth_fert_total_t", "GHG_livestock_CO2e_t")
)

## Aggregate to 1 km cell level (CELLCODE)
wm_safe <- function(x, w) if (all(is.na(x)) || sum(w[!is.na(x)]) == 0) NA_real_ else stats::weighted.mean(x, w, na.rm = TRUE)

cell_summary <- lum_summary[, .(
  EOFORIGIN                  = EOFORIGIN[1L],
  NOFORIGIN                  = NOFORIGIN[1L],
  SimUID                     = SimUID[1L],
  NUTS2                      = NUTS2[1L],
  area_ha                    = sum(area_ha),
  area_km2                   = sum(area_km2),
  forage_dm_t                = sum(forage_dm_t),
  YLDF_mean                  = sum(forage_dm_t) / sum(area_ha),
  OCPD_mean                  = wm_safe(OCPD, area_ha),
  dOCPD_mean                 = wm_safe(dOCPD, area_ha),
  NFERT_mean                 = wm_safe(NFERT, area_ha),
  NFERT_synth_mean           = wm_safe(NFERT_synth_est_kg_ha, area_ha),
  LSU_total                  = sum(LSU_allocated),
  heads_total                = sum(heads_total),
  dairy_cattle_heads         = sum(dairy_cattle_heads),
  non_dairy_cattle_heads     = sum(non_dairy_cattle_heads),
  sheep_heads                = sum(sheep_heads),
  goats_heads                = sum(goats_heads),
  milk_t                     = sum(milk_t),
  meat_t                     = sum(meat_t),
  CH4_enteric_t              = sum(CH4_enteric_t),
  CH4_manure_mgt_t           = sum(CH4_manure_mgt_t),
  N2O_manure_mgt_total_t     = sum(N2O_manure_mgt_total_t),
  N2O_pasture_prp_total_t    = sum(N2O_pasture_prp_total_t),
  N2O_manure_applied_total_t = sum(N2O_manure_applied_total_t),
  N2O_synth_fert_total_t     = sum(N2O_synth_fert_total_t),
  CO2_SOC_t                  = sum(CO2_SOC_t),
  N_excreted_total_kg        = sum(N_excreted_total_kg),
  N_left_on_pasture_kg       = sum(N_left_on_pasture_kg),
  N_applied_soils_kg         = sum(N_applied_soils_kg),
  GHG_livestock_CO2e_t       = sum(GHG_livestock_CO2e_t),
  GHG_pasture_soil_CO2e_t    = sum(GHG_pasture_soil_CO2e_t),
  GHG_total_CO2e_t           = sum(GHG_total_CO2e_t)
), by = CELLCODE]

assert_contract(
  cell_summary, sprintf("P11/%s_%s/cell_summary", lama.reg, curr.year),
  req_cols = c("CELLCODE", "EOFORIGIN", "NOFORIGIN", "area_ha", "forage_dm_t", "LSU_total", "GHG_total_CO2e_t"),
  key_cols = "CELLCODE",
  non_neg_cols = c("area_ha", "forage_dm_t", "LSU_total", "GHG_livestock_CO2e_t")
)

## Conservation checks against FAOSTAT targets & land-level sums
chk_ghg <- merge(
  alloc.sp[, .(
    ch4_ent = sum(CH4_enteric_fao_t),
    ch4_mms = sum(CH4_manure_mgt_fao_t),
    n2o_prp = sum(N2O_pasture_prp_total_t),
    nex_kg  = sum(N_excreted_total_kg)
  ), by = species],
  curr.accounts[, .(
    species,
    ch4_ent_tgt = CH4_enteric_t,
    ch4_mms_tgt = CH4_manure_mgt_t,
    n2o_prp_tgt = N2O_pasture_prp_total_t,
    nex_kg_tgt  = N_excreted_total_kg
  )],
  by = "species"
)
for (i in seq_len(nrow(chk_ghg))) {
  r <- chk_ghg[i]
  if (!is.na(r$ch4_ent_tgt) && r$ch4_ent_tgt > 0) {
    rel <- abs(r$ch4_ent - r$ch4_ent_tgt) / r$ch4_ent_tgt
    if (rel > 1e-4) stop(sprintf("[P11] CH4 enteric conservation failed for %s (%s): rel=%.3e", lama.reg, r$species, rel))
  }
}

curr.ledger[[length(curr.ledger) + 1L]] <- new_ledger_entry(
  "P11_emissions", lama.reg, curr.year, "CH4_enteric_fao_t", "t CH4",
  sum(alloc.sp$CH4_enteric_fao_t), sum(curr.accounts$CH4_enteric_t, na.rm = TRUE)
)
curr.ledger[[length(curr.ledger) + 1L]] <- new_ledger_entry(
  "P11_emissions", lama.reg, curr.year, "CO2_SOC_t", "t CO2",
  sum(cell_summary$CO2_SOC_t), sum(temp.pasture$CO2_SOC_t),
  "Checked cell_summary == lum_summary (zero species multiplication)"
)
curr.ledger[[length(curr.ledger) + 1L]] <- new_ledger_entry(
  "P11_emissions", lama.reg, curr.year, "N2O_synth_fert_total_t", "t N2O",
  sum(cell_summary$N2O_synth_fert_total_t), sum(temp.pasture$N2O_synth_fert_total_t),
  "Checked cell_summary == lum_summary (zero species multiplication)"
)

message(sprintf("  [P11] GHG total = %.2f Mt CO2e (Livestock %.2f Mt + Soil %.2f Mt, GWP=%s).",
                sum(cell_summary$GHG_total_CO2e_t) / 1e6,
                sum(cell_summary$GHG_livestock_CO2e_t) / 1e6,
                sum(cell_summary$GHG_pasture_soil_CO2e_t) / 1e6,
                GWP_VERSION))

