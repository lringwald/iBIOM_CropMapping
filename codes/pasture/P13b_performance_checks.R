##### PASTURE P13b: non-self-contained external & sub-national performance evaluation
##### Benchmarks independent of FAOSTAT national targets:
#####   Check 1: NUTS2 species livestock allocation vs. Eurostat FSS (ef_lsk_*) + Baseline A (Area) & B (Biophysical Forage)
#####   Check 2: NUTS2 total ruminant LSU (pure EPIC forage x LUM capacity) vs. Eurostat FSS total LSU
#####   Check 3: NUTS2 dairy cow milk production vs. Eurostat agr_r_milkpr (+ Baseline comparisons)
#####   Check 4: Multi-resolution SimUID area & forage agreement vs. EPIC-IIASA GRS_LUM_AreaHa_BySimUID.txt & REF
#####   Check 5: Independent national inventories: Eurostat EW-MFA MF1222 & UNFCCC National GHG Submissions

library(data.table)
library(dplyr)

if (!exists("PASTURE_RESULT_TAG")) {
  if (!file.exists("user_config.R")) stop("user_config.R not found.")
  source("user_config.R")
  source("codes/01_settings.R")
  source("codes/support/fun_pasture_contracts.R")
}

rep_dir <- file.path("output", PASTURE_RESULT_TAG, "report")
dir.create(rep_dir, recursive = TRUE, showWarnings = FALSE)
manifest_rel <- file.path("output", PASTURE_RESULT_TAG, "run_manifest.json")

agg_path  <- file.path("output", PASTURE_RESULT_TAG, "aggregated", sprintf("%s_pasture.rds", PASTURE_RESULT_TAG))
simu_path <- file.path("output", PASTURE_RESULT_TAG, "simu_res", sprintf("%s_SimU_res.rds", PASTURE_RESULT_TAG))
agg  <- readRDS(agg_path)
simu <- readRDS(simu_path)
if (!identical(agg$run_id, PASTURE_RESULT_TAG) || !identical(simu$run_id, PASTURE_RESULT_TAG)) {
  stop("[P13b] Run ID mismatch between aggregated and SimU bundles.")
}

ep_lsk  <- as.data.table(arrow::read_parquet(eurostat.priors.lsk.pq.path))
ep_milk <- as.data.table(arrow::read_parquet(eurostat.priors.milk.pq.path))
ep_mfa  <- as.data.table(arrow::read_parquet(eurostat.priors.mfa.pq.path))
epic_ref <- as.data.table(arrow::read_parquet(EPIC.grass.ref.pq.path))

safe_cor <- function(x, y, method = "pearson") {
  ok <- is.finite(x) & is.finite(y)
  if (sum(ok) < 2L || sd(x[ok]) == 0 || sd(y[ok]) == 0) return(NA_real_)
  stats::cor(x[ok], y[ok], method = method)
}
pontius_alloc_pp <- function(s_mod, s_obs) {
  100 * 0.5 * sum(abs(s_mod - s_obs), na.rm = TRUE)
}

cell_all    <- as.data.table(agg$cell_all)
nuts2_all   <- as.data.table(agg$nuts2_all)[substr(NUTS2, 1L, 2L) == region]
species_all <- as.data.table(agg$species_all)
country_all <- as.data.table(agg$country_all)
reg_years   <- unique(country_all[, .(region, year)])

## Build NUTS2 pure spatial baseline weights (area share vs EPIC forage share)
n2_space <- cell_all[substr(NUTS2, 1L, 2L) == region, .(
  area_ha     = sum(area_ha),
  forage_dm_t = sum(forage_dm_t),
  LSU_biophys = sum(LSU_total)
), by = .(region, year, NUTS2)]
n2_space[, `:=`(
  area_share_nat   = area_ha / sum(area_ha),
  forage_share_nat = forage_dm_t / sum(forage_dm_t)
), by = .(region, year)]

## ── Check 1: Sub-national NUTS2 livestock vs Eurostat FSS + Spatial Benchmarks ─
sp_nat <- species_all[, .(region, year, species, heads_nat = heads_alloc, LSU_nat = LSU_alloc,
                          lsu_per_head = fifelse(heads_alloc > 0, LSU_alloc / heads_alloc, NA_real_))]
n2_base <- merge(n2_space, sp_nat, by = c("region", "year"), allow.cartesian = TRUE)
n2_base[, `:=`(
  heads_base_area   = heads_nat * area_share_nat,
  heads_base_forage = heads_nat * forage_share_nat
)]

ep_lsk_sub <- merge(ep_lsk, reg_years, by = c("region", "year"), all = FALSE)
ep_lsk_sub <- ep_lsk_sub[!is.na(heads_fss)]

cmp_lsk <- merge(
  ep_lsk_sub[, .(region, year, NUTS2, species, fss_wave, year_gap, heads_fss)],
  nuts2_all[, .(region, year, NUTS2, species, heads_ipf = heads, LSU_ipf = LSU)],
  by = c("region", "year", "NUTS2", "species"), all.x = TRUE
)
cmp_lsk <- merge(
  cmp_lsk,
  n2_base[, .(region, year, NUTS2, species, heads_base_area, heads_base_forage, lsu_per_head)],
  by = c("region", "year", "NUTS2", "species"), all.x = TRUE
)
for (col in c("heads_ipf", "LSU_ipf", "heads_base_area", "heads_base_forage")) {
  cmp_lsk[is.na(get(col)), (col) := 0]
}
cmp_lsk[, `:=`(
  obs_share         = if (sum(heads_fss) > 0) heads_fss / sum(heads_fss) else rep(0, .N),
  ipf_share         = if (sum(heads_ipf) > 0) heads_ipf / sum(heads_ipf) else rep(0, .N),
  base_area_share   = if (sum(heads_base_area) > 0) heads_base_area / sum(heads_base_area) else rep(0, .N),
  base_forage_share = if (sum(heads_base_forage) > 0) heads_base_forage / sum(heads_base_forage) else rep(0, .N)
), by = .(region, year, species)]

perf_lsk_ctry_sp <- cmp_lsk[, .(
  n_nuts2               = .N,
  fss_wave              = fss_wave[1L],
  r_heads_ipf           = safe_cor(heads_ipf, heads_fss),
  r2_heads_ipf          = safe_cor(heads_ipf, heads_fss)^2,
  r_heads_base_area     = safe_cor(heads_base_area, heads_fss),
  r_heads_base_forage   = safe_cor(heads_base_forage, heads_fss),
  rmse_k_ipf            = sqrt(mean((heads_ipf - heads_fss)^2)) / 1e3,
  rmse_k_base_area      = sqrt(mean((heads_base_area - heads_fss)^2)) / 1e3,
  rmse_k_base_forage    = sqrt(mean((heads_base_forage - heads_fss)^2)) / 1e3,
  alloc_disagr_pp_ipf   = pontius_alloc_pp(ipf_share, obs_share),
  alloc_disagr_pp_area  = pontius_alloc_pp(base_area_share, obs_share),
  alloc_disagr_pp_forage = pontius_alloc_pp(base_forage_share, obs_share)
), by = .(region, year, species)]

perf_lsk_sp <- cmp_lsk[, .(
  n_nuts2                 = .N,
  n_countries             = uniqueN(region),
  r_heads_ipf             = safe_cor(heads_ipf, heads_fss),
  r2_heads_ipf            = safe_cor(heads_ipf, heads_fss)^2,
  r2_heads_base_area      = safe_cor(heads_base_area, heads_fss)^2,
  r2_heads_base_forage    = safe_cor(heads_base_forage, heads_fss)^2,
  r2_share_ipf            = safe_cor(ipf_share, obs_share)^2,
  r2_share_base_area      = safe_cor(base_area_share, obs_share)^2,
  r2_share_base_forage    = safe_cor(base_forage_share, obs_share)^2,
  spearman_share_ipf      = safe_cor(ipf_share, obs_share, method = "spearman"),
  rmse_k_ipf              = sqrt(mean((heads_ipf - heads_fss)^2)) / 1e3,
  rmse_k_base_area        = sqrt(mean((heads_base_area - heads_fss)^2)) / 1e3,
  rmse_k_base_forage      = sqrt(mean((heads_base_forage - heads_fss)^2)) / 1e3,
  mae_share_pp_ipf        = 100 * mean(abs(ipf_share - obs_share)),
  mae_share_pp_forage     = 100 * mean(abs(base_forage_share - obs_share)),
  mean_alloc_disagr_pp_ipf    = mean(perf_lsk_ctry_sp[species == .BY$species]$alloc_disagr_pp_ipf, na.rm = TRUE),
  mean_alloc_disagr_pp_area   = mean(perf_lsk_ctry_sp[species == .BY$species]$alloc_disagr_pp_area, na.rm = TRUE),
  mean_alloc_disagr_pp_forage = mean(perf_lsk_ctry_sp[species == .BY$species]$alloc_disagr_pp_forage, na.rm = TRUE)
), by = species]

## Soft compositional agreement (sum_k min(a_rk, o_rk)) within each NUTS2 across the 4 species
n2_comp <- cmp_lsk[, .(
  obs_lsu_tot = sum(heads_fss * lsu_per_head, na.rm = TRUE),
  ipf_lsu_tot = sum(LSU_ipf, na.rm = TRUE),
  soft_comp_agree_ipf = {
    s_o <- (heads_fss * lsu_per_head) / max(1e-12, sum(heads_fss * lsu_per_head, na.rm = TRUE))
    s_m <- LSU_ipf / max(1e-12, sum(LSU_ipf, na.rm = TRUE))
    sum(pmin(s_o, s_m))
  }
), by = .(region, year, NUTS2)]

## ── Check 2: Pure Biophysical Carrying Capacity (LUM x EPIC Forage LSU vs FSS LSU) ─
n2_cap <- merge(n2_comp, n2_space[, .(region, year, NUTS2, area_ha)], by = c("region", "year", "NUTS2"), all.x = TRUE)
n2_cap[is.na(area_ha), area_ha := 0]
n2_cap[, `:=`(
  obs_lsu_share   = { s <- sum(obs_lsu_tot, na.rm = TRUE); if (is.finite(s) && s > 0) obs_lsu_tot / s else rep(0, .N) },
  epic_lsu_share  = { s <- sum(ipf_lsu_tot, na.rm = TRUE); if (is.finite(s) && s > 0) ipf_lsu_tot / s else rep(0, .N) },
  area_lsu_share  = { s <- sum(area_ha, na.rm = TRUE);     if (is.finite(s) && s > 0) area_ha / s else rep(0, .N) }
), by = .(region, year)]

perf_nuts2_lsu <- n2_cap[, .(
  n_nuts2               = .N,
  pearson_r_lsu         = safe_cor(ipf_lsu_tot, obs_lsu_tot),
  r2_lsu                = safe_cor(ipf_lsu_tot, obs_lsu_tot)^2,
  spearman_rho_lsu      = safe_cor(ipf_lsu_tot, obs_lsu_tot, method = "spearman"),
  mae_share_pp_epic     = 100 * mean(abs(epic_lsu_share - obs_lsu_share)),
  mae_share_pp_area     = 100 * mean(abs(area_lsu_share - obs_lsu_share)),
  alloc_disagr_pp_epic  = pontius_alloc_pp(epic_lsu_share, obs_lsu_share),
  alloc_disagr_pp_area  = pontius_alloc_pp(area_lsu_share, obs_lsu_share),
  mean_soft_comp_agree  = mean(soft_comp_agree_ipf, na.rm = TRUE),
  mod_to_fss_lsu_ratio  = sum(ipf_lsu_tot) / sum(obs_lsu_tot)
), by = .(region, year)]
perf_nuts2_lsu <- merge(
  perf_nuts2_lsu,
  country_all[, .(region, year, prior_kl_div)],
  by = c("region", "year"), all.x = TRUE
)

## ── Check 3: Sub-National NUTS2 Cow Milk vs Eurostat agr_r_milkpr ────────────
ep_milk_sub <- merge(ep_milk[!is.na(milk_cow_t_eurostat)], reg_years, by = c("region", "year"), all = FALSE)
dairy_nat <- species_all[species == "dairy_cattle", .(region, year, milk_nat_t = milk_t_alloc)]
milk_mod  <- nuts2_all[species == "dairy_cattle", .(region, year, NUTS2, milk_mod_t = milk_t)]
cmp_milk <- merge(ep_milk_sub[, .(region, year, NUTS2, milk_cow_t_eurostat)], milk_mod, by = c("region", "year", "NUTS2"), all.x = TRUE)
cmp_milk <- merge(cmp_milk, n2_space[, .(region, year, NUTS2, area_share_nat, forage_share_nat)], by = c("region", "year", "NUTS2"), all.x = TRUE)
cmp_milk <- merge(cmp_milk, dairy_nat, by = c("region", "year"), all.x = TRUE)
cmp_milk[is.na(milk_mod_t), milk_mod_t := 0]
cmp_milk[, `:=`(
  milk_base_area_t   = fifelse(is.na(milk_nat_t) | is.na(area_share_nat), 0, milk_nat_t * area_share_nat),
  milk_base_forage_t = fifelse(is.na(milk_nat_t) | is.na(forage_share_nat), 0, milk_nat_t * forage_share_nat)
)]
cmp_milk[, `:=`(
  obs_share         = { s <- sum(milk_cow_t_eurostat, na.rm = TRUE); if (is.finite(s) && s > 0) milk_cow_t_eurostat / s else rep(0, .N) },
  mod_share         = { s <- sum(milk_mod_t, na.rm = TRUE);          if (is.finite(s) && s > 0) milk_mod_t / s else rep(0, .N) },
  base_forage_share = { s <- sum(milk_base_forage_t, na.rm = TRUE);  if (is.finite(s) && s > 0) milk_base_forage_t / s else rep(0, .N) }
), by = .(region, year)]

perf_milk <- cmp_milk[, .(
  n_nuts2               = .N,
  pearson_r             = safe_cor(milk_mod_t, milk_cow_t_eurostat),
  r2                    = safe_cor(milk_mod_t, milk_cow_t_eurostat)^2,
  spearman_rho          = safe_cor(milk_mod_t, milk_cow_t_eurostat, method = "spearman"),
  rmse_kt               = sqrt(mean((milk_mod_t - milk_cow_t_eurostat)^2)) / 1e3,
  mae_kt                = mean(abs(milk_mod_t - milk_cow_t_eurostat)) / 1e3,
  mae_share_pp          = 100 * mean(abs(mod_share - obs_share)),
  alloc_disagr_pp       = pontius_alloc_pp(mod_share, obs_share),
  r2_base_forage        = safe_cor(milk_base_forage_t, milk_cow_t_eurostat)^2,
  rmse_kt_base_forage   = sqrt(mean((milk_base_forage_t - milk_cow_t_eurostat)^2)) / 1e3,
  alloc_disagr_pp_forage = pontius_alloc_pp(base_forage_share, obs_share),
  mod_to_eurostat_ratio = sum(milk_mod_t) / sum(milk_cow_t_eurostat)
), by = .(region, year)]

## ── Check 4: Multi-Resolution SimUID Agreement vs EPIC GRS_LUM_AreaHa & REF ──
simu_tot <- as.data.table(simu$simu_total)
cmp_simu <- merge(
  simu_tot[, .(region, year, SimUID, lum_area_ha = area_ha, lum_forage_t = forage_dm_t, lum_yldf = YLDF_mean)],
  epic_ref[, .(SimUID, epic_managed_grass_ha, epic_total_grass_ha, YLDF_ref, forage_dm_ref_t)],
  by = "SimUID", all.x = TRUE
)
perf_simu <- cmp_simu[, .(
  n_simuid              = .N,
  n_matched_epic_ref    = sum(!is.na(epic_managed_grass_ha)),
  r_area_vs_epic_mgt    = safe_cor(lum_area_ha, epic_managed_grass_ha),
  r2_area_vs_epic_mgt   = safe_cor(lum_area_ha, epic_managed_grass_ha)^2,
  mae_area_ha           = mean(abs(lum_area_ha - epic_managed_grass_ha), na.rm = TRUE),
  area_ratio_vs_epic_mgt = sum(lum_area_ha) / sum(epic_managed_grass_ha, na.rm = TRUE),
  r_forage_vs_epic_ref  = safe_cor(lum_forage_t, forage_dm_ref_t),
  r2_forage_vs_epic_ref = safe_cor(lum_forage_t, forage_dm_ref_t)^2,
  r_yldf_vs_epic_ref    = safe_cor(lum_yldf, YLDF_ref),
  r2_yldf_vs_epic_ref   = safe_cor(lum_yldf, YLDF_ref)^2
), by = .(region, year)]

## ── Check 5: External National Benchmarks (EW-MFA MF1222 & UNFCCC CH4) ───────
perf_mfa <- country_all[, .(
  region, country, year,
  gamma_total_t_dm_lsu   = grazing_feed_coef_t_dm_lsu,
  gamma_direct_t_dm_lsu  = direct_grazing_coef_t_lsu,
  mfa_grazed_per_lsu     = mfa_grazed_per_lsu,
  direct_to_mfa_ratio    = fifelse(!is.na(mfa_grazed_per_lsu) & mfa_grazed_per_lsu > 0, direct_grazing_coef_t_lsu / mfa_grazed_per_lsu, NA_real_),
  total_to_mfa_ratio     = fifelse(!is.na(mfa_grazed_per_lsu) & mfa_grazed_per_lsu > 0, grazing_feed_coef_t_dm_lsu / mfa_grazed_per_lsu, NA_real_),
  direct_forage_share    = direct_pasture_forage_dm_t / forage_dm_t
)]

perf_unfccc_sp <- species_all[, .(
  region, year, species,
  CH4_ent_tier1_kt      = CH4_enteric_fao_t / 1e3,
  CH4_ent_unfccc_kt     = CH4_enteric_unfccc_t / 1e3,
  ent_rel_diff_pct      = 100 * (CH4_enteric_fao_t - CH4_enteric_unfccc_t) / CH4_enteric_unfccc_t,
  CH4_man_tier1_kt      = CH4_manure_mgt_fao_t / 1e3,
  CH4_man_unfccc_kt     = CH4_manure_mgt_unfccc_t / 1e3,
  man_rel_diff_pct      = 100 * (CH4_manure_mgt_fao_t - CH4_manure_mgt_unfccc_t) / CH4_manure_mgt_unfccc_t
)]

perf_unfccc_ctry <- perf_unfccc_sp[, .(
  CH4_ent_tier1_kt   = sum(CH4_ent_tier1_kt, na.rm = TRUE),
  CH4_ent_unfccc_kt  = sum(CH4_ent_unfccc_kt, na.rm = TRUE),
  ent_rel_diff_pct   = 100 * (sum(CH4_ent_tier1_kt, na.rm = TRUE) - sum(CH4_ent_unfccc_kt, na.rm = TRUE)) / sum(CH4_ent_unfccc_kt, na.rm = TRUE),
  CH4_man_tier1_kt   = sum(CH4_man_tier1_kt, na.rm = TRUE),
  CH4_man_unfccc_kt  = sum(CH4_man_unfccc_kt, na.rm = TRUE),
  man_rel_diff_pct   = 100 * (sum(CH4_man_tier1_kt, na.rm = TRUE) - sum(CH4_man_unfccc_kt, na.rm = TRUE)) / sum(CH4_man_unfccc_kt, na.rm = TRUE),
  r_sp_ch4_ent       = safe_cor(CH4_ent_tier1_kt, CH4_ent_unfccc_kt),
  rmse_sp_ch4_ent_kt = sqrt(mean((CH4_ent_tier1_kt - CH4_ent_unfccc_kt)^2, na.rm = TRUE))
), by = .(region, year)]

## Save CSV, Parquet, JSON sidecars, and performance_summary.rds
out_tables <- list(
  performance_nuts2_livestock_by_species = perf_lsk_sp,
  performance_nuts2_total_lsu            = perf_nuts2_lsu,
  performance_nuts2_milk                 = perf_milk,
  performance_simu_epic_benchmark        = perf_simu,
  performance_forage_mfa_benchmark       = perf_mfa,
  performance_ghg_unfccc_benchmark       = perf_unfccc_ctry
)
for (nm in names(out_tables)) {
  fwrite(out_tables[[nm]], file.path(rep_dir, paste0(nm, ".csv")))
  pq_p <- file.path(rep_dir, paste0(nm, ".parquet"))
  save_parquet_atomic(out_tables[[nm]], pq_p)
  write_output_sidecar(
    data_path     = pq_p,
    product_name  = nm,
    run_id        = PASTURE_RESULT_TAG,
    year          = paste(sort(unique(country_all$year)), collapse = ","),
    manifest_path = manifest_rel
  )
}

perf_bundle <- list(
  run_id            = PASTURE_RESULT_TAG,
  lsk_by_species    = perf_lsk_sp,
  lsk_by_ctry_sp    = perf_lsk_ctry_sp,
  lsk_scatter_df    = cmp_lsk[, .(region, year, NUTS2, species, heads_fss, heads_ipf, heads_base_area, heads_base_forage)],
  nuts2_total_lsu   = perf_nuts2_lsu,
  nuts2_milk        = perf_milk,
  milk_scatter_df   = cmp_milk[, .(region, year, NUTS2, milk_cow_t_eurostat, milk_mod_t, milk_base_forage_t)],
  simu_benchmark    = perf_simu,
  simu_scatter_df   = cmp_simu[, .(region, year, SimUID, lum_area_ha, epic_managed_grass_ha, lum_forage_t, forage_dm_ref_t)],
  mfa_benchmark     = perf_mfa,
  unfccc_by_species = perf_unfccc_sp,
  unfccc_by_country = perf_unfccc_ctry
)
save_rds_atomic(perf_bundle, file.path(rep_dir, "performance_summary.rds"))

message("  [P13b] Saved 5 non-self-contained external & sub-national performance benchmarks into ", rep_dir)

