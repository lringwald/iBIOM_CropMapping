##### PASTURE P16: dynamic report objects, EU maps, Markdown + self-contained HTML run report
##### Adheres to reporting-publication.md (dynamic report bundle, working-draft banner,
##### zero hardcoded result values, auto-generated technical appendix from run_manifest).

library(dplyr)
library(tidyr)
library(data.table)
library(ggplot2)
library(patchwork)

if (!exists("PASTURE_RESULT_TAG")) {
  if (!file.exists("user_config.R")) stop("user_config.R not found.")
  source("user_config.R")
  source("codes/01_settings.R")
  source("codes/support/fun_pasture_contracts.R")
}
if (!exists("gwp_pair")) {
  pasture_constants <- load_pasture_constants(pasture.params.csv)
  gwp_pair <- resolve_gwp(GWP_VERSION, pasture_constants)
}

rep.dir <- file.path("output", PASTURE_RESULT_TAG, "report")
fig.dir <- file.path(rep.dir, "fig")
dir.create(fig.dir, recursive = TRUE, showWarnings = FALSE)

agg_path      <- file.path("output", PASTURE_RESULT_TAG, "aggregated", sprintf("%s_pasture.rds", PASTURE_RESULT_TAG))
simu_path     <- file.path("output", PASTURE_RESULT_TAG, "simu_res", sprintf("%s_SimU_res.rds", PASTURE_RESULT_TAG))
perf_path     <- file.path(rep.dir, "performance_summary.rds")
manifest_path <- file.path("output", PASTURE_RESULT_TAG, "run_manifest.rds")

agg  <- readRDS(agg_path)
simu <- readRDS(simu_path)
perf <- if (file.exists(perf_path)) readRDS(perf_path) else NULL
man  <- readRDS(manifest_path)

if (!identical(agg$run_id, PASTURE_RESULT_TAG) || !identical(simu$run_id, PASTURE_RESULT_TAG) || !identical(man$run_id, PASTURE_RESULT_TAG)) {
  stop("[P16] Suite/run_id mismatch between aggregated, SimU, and manifest files.")
}
if (!is.null(perf) && !identical(perf$run_id, PASTURE_RESULT_TAG)) {
  stop("[P16] Performance bundle run_id mismatch.")
}

fmt  <- function(x, d = 0) formatC(x, format = "f", digits = d, big.mark = ",")
pct  <- function(a, b) ifelse(b > 0, 100 * a / b, NA_real_)
md_table <- function(df, align = NULL) paste(knitr::kable(df, format = "pipe", align = align), collapse = "\n")

cell_all    <- copy(agg$cell_all)
species_all <- as_tibble(agg$species_all)
country_all <- as_tibble(agg$country_all)
ledger_all  <- as_tibble(agg$ledger)
fallbacks   <- as_tibble(agg$fallbacks)
run_years   <- paste(sort(unique(country_all$year)), collapse = ", ")

## Write CSV tables into report/
fwrite(country_all, file.path(rep.dir, "country_summary.csv"))
fwrite(species_all, file.path(rep.dir, "species_targets_fulfilment.csv"))
fwrite(ledger_all,  file.path(rep.dir, "conservation_ledger.csv"))
fwrite(fallbacks,   file.path(rep.dir, "fallbacks_log.csv"))

## ── Build Report Objects Bundle (single source of truth for text + plots) ──
eu_totals <- country_all %>%
  summarise(
    n_countries = n(),
    pasture_Mha = sum(pasture_area_ha) / 1e6,
    forage_Mt   = sum(forage_dm_t) / 1e6,
    LSU_M       = sum(LSU_total) / 1e6,
    milk_Mt     = sum(species_all$milk_t_alloc, na.rm = TRUE) / 1e6,
    meat_kt     = sum(species_all$meat_t_alloc, na.rm = TRUE) / 1e3,
    GHG_lsk_Mt  = sum(GHG_livestock_CO2e_t) / 1e6,
    GHG_soil_Mt = sum(GHG_pasture_soil_CO2e_t) / 1e6,
    GHG_tot_Mt  = sum(GHG_total_CO2e_t) / 1e6
  )

max_ledger_err <- max(abs(ledger_all$rel_diff), na.rm = TRUE)

report_objects <- list(
  run_id               = PASTURE_RESULT_TAG,
  git_commit           = man$git_commit,
  git_branch           = man$git_branch,
  git_dirty            = man$git_dirty,
  engine_cascade_core  = man$engine_cascade_core,
  created_utc          = format(Sys.time(), "%Y-%m-%dT%H:%M:%SZ", tz = "UTC"),
  eu_totals      = eu_totals,
  max_ledger_err = max_ledger_err,
  country_all    = country_all,
  species_all    = species_all,
  ledger_all     = ledger_all,
  fallbacks      = fallbacks,
  performance    = perf,
  simu_coverage  = simu$simu_total[, .(area_ha = sum(area_ha), LSU = sum(LSU_total)), by = .(region, year)]
)
save_rds_atomic(report_objects, file.path(rep.dir, "report_objects.rds"))

## ── Figures ─────────────────────────────────────────────────────────────────

## 1. 1 km EU Overview Map & Production/Soil Map
maps.ok <- requireNamespace("giscoR", quietly = TRUE) && requireNamespace("sf", quietly = TRUE)
eu_bg <- if (maps.ok) tryCatch(giscoR::gisco_get_countries(region = "Europe"), error = function(e) NULL) else NULL
maps.ok <- !is.null(eu_bg)

if (maps.ok) {
  bg <- sf::st_transform(eu_bg, 3035)
  ## Collapse border-duplicated coordinates cleanly by summing extensive & area-weighting intensive
  map_dt <- cell_all[, .(
    area_ha          = sum(area_ha),
    forage_dm_t      = sum(forage_dm_t),
    LSU_total        = sum(LSU_total),
    milk_t           = sum(milk_t),
    meat_t           = sum(meat_t),
    CO2_SOC_t        = sum(CO2_SOC_t),
    GHG_total_CO2e_t = sum(GHG_total_CO2e_t),
    x                = EOFORIGIN[1L] + 500,
    y                = NOFORIGIN[1L] + 500
  ), by = CELLCODE]
  map_dt[, `:=`(
    pasture_pct = pmin(100, area_ha),
    yldf_ha     = forage_dm_t / area_ha,
    lsu_ha      = LSU_total / area_ha,
    ghg_co2e_ha = GHG_total_CO2e_t / area_ha,
    soc_co2_ha  = CO2_SOC_t / area_ha,
    milk_km2    = milk_t,
    meat_km2    = meat_t
  )]

  ## Scope map extent tightly around included countries + small margin
  xr <- range(map_dt$x); yr <- range(map_dt$y)
  xlim <- c(xr[1] - 1.5e5, xr[2] + 1.5e5)
  ylim <- c(yr[1] - 1.5e5, yr[2] + 1.5e5)

  ov_panel <- function(fill_aes, scale, title) {
    ggplot() +
      geom_sf(data = bg, fill = "grey93", colour = NA) +
      geom_raster(data = map_dt, aes(x = x, y = y, fill = {{ fill_aes }})) +
      geom_sf(data = bg, fill = NA, colour = "grey45", linewidth = 0.2) +
      scale +
      coord_sf(crs = 3035, xlim = xlim, ylim = ylim, expand = FALSE, datum = NA) +
      labs(title = title, x = NULL, y = NULL) +
      theme_void(base_size = 10) +
      theme(plot.title = element_text(face = "bold", hjust = 0.02),
            legend.position = "right",
            panel.background = element_rect(fill = "#dfe9f2", colour = NA))
  }

  cap99 <- function(v) signif(quantile(v[is.finite(v)], 0.99, na.rm = TRUE), 2)
  lsu_cap <- cap99(map_dt$lsu_ha)
  ghg_cap <- cap99(abs(map_dt$ghg_co2e_ha))
  mk_cap  <- cap99(map_dt$milk_km2)
  mt_cap  <- cap99(map_dt$meat_km2)
  soc_cap <- cap99(abs(map_dt$soc_co2_ha))

  p1 <- ov_panel(pasture_pct,
                 scale_fill_distiller(palette = "YlGn", direction = 1, limits = c(0, 100), name = "% of cell"),
                 "Pasture & grassland share (LUM 15-25)")
  p2 <- ov_panel(pmin(yldf_ha, cap99(map_dt$yldf_ha)),
                 scale_fill_viridis_c(option = "viridis", name = "t DM/ha"),
                 "EPIC forage yield (YLDF)")
  p3 <- ov_panel(pmin(lsu_ha, lsu_cap),
                 scale_fill_viridis_c(option = "rocket", direction = -1, limits = c(0, lsu_cap), name = "LSU/ha"),
                 sprintf("Sustained stocking density (capped at %s)", lsu_cap))
  p4 <- ov_panel(pmax(pmin(ghg_co2e_ha, ghg_cap), -ghg_cap),
                 scale_fill_gradient2(low = "#2166ac", mid = "white", high = "#b2182b", midpoint = 0,
                                      limits = c(-ghg_cap, ghg_cap), name = "t CO2e/ha"),
                 sprintf("Net livestock + pasture GHG (%s)", GWP_VERSION))

  fig00 <- (p1 | p2) / (p3 | p4) +
    plot_annotation(
      title = sprintf("Downscaled Pasture & Livestock Overview (%s, 1 km, run %s)", run_years, PASTURE_RESULT_TAG),
      caption = sprintf("Working draft | Commit %s | Grazing coef gamma_c = EPIC Forage / FAOSTAT LSU", substr(man$git_commit, 1, 7)),
      theme = theme(plot.title = element_text(face = "bold", size = 13))
    )
  ggsave(file.path(fig.dir, "00_eu_pasture_overview.png"), fig00, width = 12, height = 9.5, dpi = 220, bg = "white")

  p5 <- ov_panel(pmin(milk_km2, mk_cap),
                 scale_fill_distiller(palette = "Blues", direction = 1, limits = c(0, mk_cap), name = "t/km^2"),
                 sprintf("Milk production (capped at %s)", mk_cap))
  p6 <- ov_panel(pmin(meat_km2, mt_cap),
                 scale_fill_distiller(palette = "OrRd", direction = 1, limits = c(0, mt_cap), name = "t/km^2"),
                 sprintf("Ruminant meat production (capped at %s)", mt_cap))
  p7 <- ov_panel(pmax(pmin(soc_co2_ha, soc_cap), -soc_cap),
                 scale_fill_gradient2(low = "#2166ac", mid = "white", high = "#b2182b", midpoint = 0,
                                      limits = c(-soc_cap, soc_cap), name = "t CO2/ha"),
                 "Pasture SOC CO2 flux (- = uptake)")
  fig01 <- (p5 | p6 | p7) +
    plot_annotation(
      title = sprintf("Milk, Meat & Pasture Soil Carbon Flux (%s, 1 km, run %s)", run_years, PASTURE_RESULT_TAG),
      theme = theme(plot.title = element_text(face = "bold", size = 13))
    )
  ggsave(file.path(fig.dir, "01_eu_production_and_soil.png"), fig01, width = 16, height = 5.4, dpi = 220, bg = "white")
}

## 2. Independent Non-Self-Contained Performance Checks Figure (replaces tautological target-hit plot)
perf_plot_src <- file.path("output", PASTURE_RESULT_TAG, "plot", "pasture_independent_performance.png")
if (file.exists(perf_plot_src)) {
  file.copy(perf_plot_src, file.path(fig.dir, "02_independent_performance_checks.png"), overwrite = TRUE)
}

## 3. Grazing feed coefficient (total & direct) vs Eurostat MF1222 / LSU
coef_df <- country_all %>%
  select(
    region,
    `Total gamma_c (LUM 15-25 / LSU)`       = grazing_feed_coef_t_dm_lsu,
    `Direct Pasture gamma_c (15-18, 23-25)` = direct_grazing_coef_t_lsu,
    `Eurostat MF1222 / LSU`                 = mfa_grazed_per_lsu
  ) %>%
  pivot_longer(-region, names_to = "Benchmark", values_to = "t_dm_lsu")
fig03 <- ggplot(coef_df, aes(x = region, y = t_dm_lsu, fill = Benchmark)) +
  geom_col(position = position_dodge(width = 0.65), width = 0.55) +
  labs(title = sprintf("Endogenous grazing feed coefficient vs Eurostat EW-MFA MF1222 (%s)", run_years),
       x = "Country", y = "t DM / LSU / yr", fill = NULL) +
  theme_bw() + theme(legend.position = "bottom")
ggsave(file.path(fig.dir, "03_grazing_feed_coefficient_comparison.png"), fig03, width = 9.5, height = 5, dpi = 220, bg = "white")

## 4. Stacked GHG breakdown + FAO TIER 1 vs UNFCCC enteric/MMS comparison
ghg_stack <- cell_all %>%
  group_by(region) %>%
  summarise(
    `Enteric CH4`       = sum(CH4_enteric_t) * gwp_pair[["CH4"]] / 1e6,
    `Manure Mgt CH4`    = sum(CH4_manure_mgt_t) * gwp_pair[["CH4"]] / 1e6,
    `Manure Mgt N2O`    = sum(N2O_manure_mgt_total_t) * gwp_pair[["N2O"]] / 1e6,
    `Pasture PRP N2O`   = sum(N2O_pasture_prp_total_t) * gwp_pair[["N2O"]] / 1e6,
    `Manure Appl N2O`   = sum(N2O_manure_applied_total_t) * gwp_pair[["N2O"]] / 1e6,
    `Synth N Fert N2O`  = sum(N2O_synth_fert_total_t) * gwp_pair[["N2O"]] / 1e6,
    `Pasture SOC CO2`   = sum(CO2_SOC_t) / 1e6,
    .groups = "drop"
  ) %>%
  pivot_longer(-region, names_to = "Source", values_to = "Mt_CO2e")

fig04_left <- ggplot(ghg_stack, aes(x = region, y = Mt_CO2e, fill = Source)) +
  geom_col() +
  geom_hline(yintercept = 0, colour = "black", linewidth = 0.3) +
  labs(title = sprintf("Full GHG budget by pathway (Mt CO2e, %s)", GWP_VERSION), x = "Country", y = "Mt CO2e/yr") +
  theme_bw() + theme(legend.position = "bottom")

unf_comp <- species_all %>%
  group_by(region) %>%
  summarise(
    `FAO TIER 1` = sum(CH4_enteric_fao_t + CH4_manure_mgt_fao_t, na.rm = TRUE) / 1e3,
    `UNFCCC`     = sum(CH4_enteric_unfccc_t + CH4_manure_mgt_unfccc_t, na.rm = TRUE) / 1e3,
    .groups = "drop"
  ) %>%
  pivot_longer(-region, names_to = "Inventory", values_to = "kt_CH4")

fig04_right <- ggplot(unf_comp, aes(x = region, y = kt_CH4, fill = Inventory)) +
  geom_col(position = position_dodge(width = 0.65), width = 0.55) +
  labs(title = "CH4 (Enteric + Manure Mgt): FAO TIER 1 vs UNFCCC", x = "Country", y = "kt CH4/yr", fill = NULL) +
  theme_bw() + theme(legend.position = "bottom")

fig04 <- fig04_left | fig04_right
ggsave(file.path(fig.dir, "04_ghg_breakdown_and_sources.png"), fig04, width = 13, height = 5.5, dpi = 220, bg = "white")

## ── Build Markdown + Self-Contained HTML Report ──────────────────────────────
ctry_md <- country_all %>% transmute(
  Country             = region,
  `Area (km^2)`       = fmt(pasture_area_ha / 100),
  `Mean YLDF (t/ha)`  = fmt(mean_YLDF_t_ha, 2),
  `Forage (Mt DM)`    = fmt(forage_dm_t / 1e6, 2),
  `LSU (M)`           = fmt(LSU_total / 1e6, 3),
  `gamma_c (tot)`     = fmt(grazing_feed_coef_t_dm_lsu, 2),
  `gamma_c (direct)`  = fmt(direct_grazing_coef_t_lsu, 2),
  `MF1222/LSU`        = ifelse(is.na(mfa_grazed_per_lsu), "n/a", fmt(mfa_grazed_per_lsu, 2)),
  `Net GHG (Mt CO2e)` = fmt(GHG_total_CO2e_t / 1e6, 2),
  `KL prior div`      = ifelse(is.na(prior_kl_div), "n/a", fmt(prior_kl_div, 3)),
  `COG vs tbl err`    = ifelse(is.na(raster_table_max_rel_diff), "n/a", sprintf("%.1e", raster_table_max_rel_diff))
)

perf_lsk_md <- if (!is.null(perf)) {
  as_tibble(perf$lsk_by_species) %>% transmute(
    Species               = species,
    `NUTS2`               = n_nuts2,
    `R2 (IPF)`            = fmt(r2_heads_ipf, 3),
    `R2 (Forage base)`    = fmt(r2_heads_base_forage, 3),
    `R2 (Area base)`      = fmt(r2_heads_base_area, 3),
    `RMSE k (IPF / Base)` = paste0(fmt(rmse_k_ipf, 1), " / ", fmt(rmse_k_base_forage, 1)),
    `Alloc Disagr pp (IPF / Base)` = paste0(fmt(mean_alloc_disagr_pp_ipf, 1), " / ", fmt(mean_alloc_disagr_pp_forage, 1))
  )
} else data.frame(Note = "Run P13b_performance_checks.R first.")

perf_cap_md <- if (!is.null(perf)) {
  merge(
    as_tibble(perf$nuts2_total_lsu),
    as_tibble(perf$nuts2_milk)[, c("region", "year", "r2", "rmse_kt", "alloc_disagr_pp", "r2_base_forage")],
    by = c("region", "year"), all.x = TRUE
  ) %>% transmute(
    Country            = region,
    `NUTS2`            = n_nuts2,
    `Biophys LSU R2`   = fmt(r2_lsu, 3),
    `Biophys Spearman` = fmt(spearman_rho_lsu, 3),
    `Soft Comp Agree`  = fmt(mean_soft_comp_agree, 3),
    `Milk R2 (Mod/Base)` = paste0(fmt(r2, 3), " / ", fmt(r2_base_forage, 3)),
    `Milk RMSE (kt)`   = fmt(rmse_kt, 1),
    `Milk Disagr (pp)` = fmt(alloc_disagr_pp, 1)
  )
} else data.frame(Note = "Run P13b_performance_checks.R first.")

perf_simu_unf_md <- if (!is.null(perf)) {
  merge(as_tibble(perf$simu_benchmark), as_tibble(perf$unfccc_by_country), by = c("region", "year"), all.x = TRUE) %>%
    transmute(
      Country                = region,
      `SimUIDs`              = fmt(n_simuid),
      `Area R2 vs EPIC X15-25` = fmt(r2_area_vs_epic_mgt, 3),
      `Area MAE (ha)`        = fmt(mae_area_ha, 1),
      `Forage R2 vs REF`     = fmt(r2_forage_vs_epic_ref, 3),
      `Tier1 vs UNFCCC ent CH4` = sprintf("%+.1f%%", ent_rel_diff_pct),
      `Tier1 vs UNFCCC man CH4` = sprintf("%+.1f%%", man_rel_diff_pct),
      `Species r (UNFCCC)`   = fmt(r_sp_ch4_ent, 3)
    )
} else data.frame(Note = "Run P13b_performance_checks.R first.")

sp_md <- species_all %>% transmute(
  Country        = region,
  Species        = species,
  `Heads (k)`    = fmt(heads_alloc / 1e3, 1),
  `LSU (k)`      = fmt(LSU_alloc / 1e3, 1),
  `Milk (kt)`    = fmt(milk_t_alloc / 1e3, 1),
  `Meat (kt)`    = fmt(meat_t_alloc / 1e3, 1),
  `CH4 ent (kt)` = fmt(CH4_enteric_t / 1e3, 2),
  `Lsk GHG (Mt)` = fmt(GHG_livestock_CO2e_t / 1e6, 2)
)

fb_md <- if (nrow(fallbacks) > 0L) {
  fallbacks %>% transmute(
    Stage = stage, Country = region, Year = year, Kind = kind,
    Used = used, `Affected` = ifelse(is.na(affected_share), "-", paste0(fmt(100 * affected_share, 2), "%"))
  )
} else data.frame(Note = "No fallbacks triggered.")

map_md <- function(name, alt) if (file.exists(file.path(fig.dir, name))) c(sprintf("![%s](fig/%s)", alt, name), "") else NULL

L <- c(
  sprintf("# Pasture & Ruminant Livestock Disaggregation — Run Report `%s`", PASTURE_RESULT_TAG),
  "",
  "> **Document Tier: Working Draft** — Generated strictly from report bundle `report_objects.rds` and `run_manifest.rds`. Do not distribute outside the team without promoting to a full EU-27+UK release.",
  "",
  sprintf("**Year(s):** %s &nbsp;|&nbsp; **Countries:** %d &nbsp;|&nbsp; **GWP:** %s (`CH4=%g`, `N2O=%g`) &nbsp;|&nbsp; **Report created:** %s",
          run_years, eu_totals$n_countries, GWP_VERSION, gwp_pair[["CH4"]], gwp_pair[["N2O"]], format(Sys.Date())),
  "",
  sprintf("**Code:** branch `%s`, commit `%s`%s",
          man$git_branch, substr(man$git_commit, 1, 7),
          if (isTRUE(man$git_dirty)) " (**uncommitted working-tree changes present during run**)" else ""),
  "",
  "## 1. Summary",
  "",
  sprintf("* **Total pasture area (LUM %s):** %s Mha producing %s Mt DM of EPIC forage biomass.",
          paste(range(lum_grass_map), collapse = "-"), fmt(eu_totals$pasture_Mha, 2), fmt(eu_totals$forage_Mt, 2)),
  sprintf("* **Livestock & production reconciled 100%% to FAOSTAT:** %s M LSU, %s Mt raw milk, %s kt carcass meat.",
          fmt(eu_totals$LSU_M, 2), fmt(eu_totals$milk_Mt, 2), fmt(eu_totals$meat_kt, 0)),
  sprintf("* **Full GHG budget (%s):** %s Mt CO2e/yr net (%s Mt CO2e livestock; %s Mt CO2e pasture soils).",
          GWP_VERSION, fmt(eu_totals$GHG_tot_Mt, 2), fmt(eu_totals$GHG_lsk_Mt, 2), fmt(eu_totals$GHG_soil_Mt, 2)),
  sprintf("* **Conservation ledger:** max relative deviation across all stages and checks = `%.2e`.", max_ledger_err),
  "",
  map_md("00_eu_pasture_overview.png", "Pasture & Livestock 1 km Overview"),
  map_md("01_eu_production_and_soil.png", "Milk, Meat & Soil C Flux"),
  "## 2. Country Summary & Endogenous Grazing Feed Coefficient",
  "",
  "The endogenous country grazing feed coefficient is $\\gamma_c = B_c / \\text{LSU}_c$ (t DM EPIC forage per FAOSTAT LSU per yr). Eurostat EW-MFA direct grazed biomass (`MF1222` at 15% moisture $\\times 0.85$ / $\\text{LSU}_c$) is shown alongside as an external accounting benchmark.",
  "",
  md_table(ctry_md, align = c("l", rep("r", ncol(ctry_md) - 1))),
  "",
  "![Grazing feed coefficient vs MF1222](fig/03_grazing_feed_coefficient_comparison.png)",
  "",
  "## 3. Non-Self-Contained Performance Evaluation (Independent External Benchmarks)",
  "",
  "All national FAOSTAT targets match 100% by construction (verified in the conservation ledger in Appendix 5). To evaluate **spatial allocation skill and inventory accuracy without circularity**, the model is benchmarked against independent Eurostat NUTS2 survey/statistical data (`ef_lsk_*`, `agr_r_milkpr`), spatial no-prior baselines (Uniform Area & Biophysical Forage), EPIC-IIASA raw `GRS_LUM_AreaHa_BySimUID` / `REF` tables, Eurostat EW-MFA `MF1222`, and national UNFCCC submissions.",
  "",
  map_md("02_independent_performance_checks.png", "Independent External & Sub-National Performance Benchmarks"),
  "### 3.1 Sub-National NUTS2 Livestock Allocation vs. Eurostat FSS (`ef_lsk_*`) & Baselines",
  "",
  md_table(perf_lsk_md, align = c("l", rep("r", ncol(perf_lsk_md) - 1))),
  "",
  "### 3.2 Pure Biophysical Carrying Capacity (`LUM x EPIC Forage`) & Regional Milk (`agr_r_milkpr`)",
  "",
  md_table(perf_cap_md, align = c("l", rep("r", ncol(perf_cap_md) - 1))),
  "",
  "### 3.3 Multi-Resolution `SimUID` EPIC Benchmark & UNFCCC GHG Inventory Comparison",
  "",
  md_table(perf_simu_unf_md, align = c("l", rep("r", ncol(perf_simu_unf_md) - 1))),
  "",
  "### 3.4 Species Allocation Summary",
  "",
  md_table(sp_md, align = c("l", "l", rep("r", ncol(sp_md) - 2))),
  "",
  "## 4. Full GHG Emissions Breakdown",
  "",
  "![GHG breakdown and source comparison](fig/04_ghg_breakdown_and_sources.png)",
  "",
  "## 5. Technical Appendix (Generated from Manifest)",
  "",
  "### 5.1 Fallbacks & Imputations Logged",
  "",
  md_table(fb_md),
  "",
  "### 5.2 Resolved Configuration & Software",
  "",
  sprintf("* `INPUT_DIR = \"%s\"`, `LIVESTOCK_ACCOUNTING_SOURCE = \"%s\"`, `FAOSTAT_EMISSION_SOURCE = \"%s\"`, `USE_EUROSTAT_PRIORS = %s`, `GWP_VERSION = \"%s\"`, `lum_grass_map = %s`",
          INPUT_DIR, LIVESTOCK_ACCOUNTING_SOURCE, FAOSTAT_EMISSION_SOURCE, USE_EUROSTAT_PRIORS, GWP_VERSION, paste(range(lum_grass_map), collapse = ":")),
  sprintf("* `%s`, `terra %s`, `sf %s`, `data.table %s`, `eurostat %s`, `arrow %s`",
          R.version.string, as.character(packageVersion("terra")), as.character(packageVersion("sf")),
          as.character(packageVersion("data.table")), as.character(packageVersion("eurostat")), as.character(packageVersion("arrow"))),
  {
    eng <- man$engine_cascade_core
    if (is.list(eng) && length(eng) > 0L) {
      sprintf("* **IPF solver:** `cascadecore::fienberg` v%s (%s: `%s`, commit `%s`%s)",
              eng$version, eng$source, eng$path,
              if (is.null(eng$commit) || is.na(eng$commit)) "vendored" else substr(eng$commit, 1L, 7L),
              if (isTRUE(eng$dirty)) ", uncommitted changes" else "")
    } else {
      "* **IPF solver:** `cascadecore::fienberg`"
    }
  },
  ""
)

md_file <- file.path(rep.dir, sprintf("%s_run_report.md", PASTURE_RESULT_TAG))
write_lines_atomic(unlist(L), md_file)

css <- "body{font-family:Segoe UI,Helvetica,Arial,sans-serif;max-width:1100px;margin:2em auto;padding:0 1em;line-height:1.45;color:#222}
blockquote{border-left:4px solid #c0392b;background:#fdf2f2;padding:8px 12px;margin:1em 0}
table{border-collapse:collapse;font-size:0.85em;margin:0.5em 0 1em}th,td{border:1px solid #ccc;padding:3px 8px}th{background:#f0f3f7}
img{max-width:100%}code{background:#f4f4f4;padding:0 3px}h1{font-size:1.5em}h2{border-bottom:1px solid #ddd;padding-bottom:3px}"
html <- markdown::mark(text = paste(unlist(L), collapse = "\n"), options = "+tables")
for (img in unique(regmatches(html, gregexpr('src="fig/[^"]+"', html))[[1]])) {
  p <- sub('^src="(.*)"$', "\\1", img)
  img_abs <- file.path(rep.dir, p)
  if (file.exists(img_abs)) {
    html <- gsub(img, paste0('src="', knitr::image_uri(img_abs), '"'), html, fixed = TRUE)
  }
}
write_lines_atomic(
  c("<!DOCTYPE html><html><head><meta charset=\"utf-8\">",
    sprintf("<title>Pasture Run Report %s</title><style>%s</style></head><body>", PASTURE_RESULT_TAG, css),
    html, "</body></html>"),
  sub("[.]md$", ".html", md_file)
)

message("  [P16] Run report written to ", md_file, " (+ .html)")

