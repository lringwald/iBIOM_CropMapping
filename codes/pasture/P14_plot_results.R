##### PASTURE P14: non-self-contained verification plots into output/<PASTURE_RESULT_TAG>/plot/

library(data.table)
library(dplyr)
library(tidyr)
library(ggplot2)
library(patchwork)

agg_path  <- file.path("output", PASTURE_RESULT_TAG, "aggregated", sprintf("%s_pasture.rds", PASTURE_RESULT_TAG))
perf_path <- file.path("output", PASTURE_RESULT_TAG, "report", "performance_summary.rds")
agg <- readRDS(agg_path)
if (!identical(agg$run_id, PASTURE_RESULT_TAG)) stop("[P14] Run ID mismatch.")

plot_dir <- file.path("output", PASTURE_RESULT_TAG, "plot")
dir.create(plot_dir, recursive = TRUE, showWarnings = FALSE)

ctry <- as_tibble(agg$country_all)

## 1. Country grazing feed coefficient (total & direct) vs Eurostat MF1222
coef_df <- ctry %>%
  select(
    region,
    `Total gamma_c (LUM 15-25 / LSU)`        = grazing_feed_coef_t_dm_lsu,
    `Direct Pasture gamma_c (15-18, 23-25)`  = direct_grazing_coef_t_lsu,
    `Eurostat EW-MFA MF1222 / LSU`           = mfa_grazed_per_lsu
  ) %>%
  pivot_longer(-region, names_to = "metric", values_to = "t_dm_lsu")

p_coef <- ggplot(coef_df, aes(x = region, y = t_dm_lsu, fill = metric)) +
  geom_col(position = position_dodge(width = 0.7), width = 0.6) +
  labs(
    title = sprintf("Endogenous grazing feed coefficients vs Eurostat EW-MFA MF1222 (%s)", PASTURE_RESULT_TAG),
    x = "Country", y = "t DM / LSU / yr", fill = NULL
  ) +
  theme_bw() +
  theme(legend.position = "bottom")

ggsave(file.path(plot_dir, "grazing_feed_coef_and_mfa.png"), p_coef, width = 9.5, height = 5, dpi = 220, bg = "white")

## 2. Independent Non-Self-Contained Performance Suite (when P13b bundle exists)
if (file.exists(perf_path)) {
  perf <- readRDS(perf_path)
  if (!identical(perf$run_id, PASTURE_RESULT_TAG)) stop("[P14] Performance bundle run_id mismatch.")

  lsk_long <- perf$lsk_scatter_df %>%
    as_tibble() %>%
    filter(heads_fss > 0) %>%
    select(region, species, heads_fss, `Downscaled (2D IPF + FSS Prior)` = heads_ipf, `Baseline (Biophysical Forage Only)` = heads_base_forage) %>%
    pivot_longer(-c(region, species, heads_fss), names_to = "Model", values_to = "heads_pred") %>%
    filter(heads_pred > 0)

  pa <- ggplot(lsk_long, aes(x = heads_fss / 1e3, y = heads_pred / 1e3, colour = Model, shape = region)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey35") +
    geom_point(alpha = 0.8, size = 2.2) +
    scale_x_log10(labels = scales::comma) +
    scale_y_log10(labels = scales::comma) +
    facet_wrap(~ species, scales = "free") +
    labs(title = "A. NUTS2 Heads vs Eurostat FSS (ef_lsk_*)", x = "Eurostat FSS (k heads)", y = "Predicted (k heads)", colour = NULL, shape = "Country") +
    theme_bw(base_size = 9.5) + theme(legend.position = "bottom")

  mk_df <- perf$milk_scatter_df %>% as_tibble() %>% filter(milk_cow_t_eurostat > 0, milk_mod_t > 0)
  pb <- ggplot(mk_df, aes(x = milk_cow_t_eurostat / 1e3, y = milk_mod_t / 1e3, colour = region)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey35") +
    geom_point(size = 2.4, alpha = 0.85) +
    labs(title = "B. NUTS2 Cow Milk vs Eurostat (agr_r_milkpr)", x = "Eurostat agr_r_milkpr (kt)", y = "Downscaled Milk (kt)", colour = "Country") +
    theme_bw(base_size = 9.5) + theme(legend.position = "bottom")

  sm_df <- perf$simu_scatter_df %>% as_tibble() %>% filter(!is.na(epic_managed_grass_ha))
  if (nrow(sm_df) > 8000L) {
    set.seed(42)
    sm_df <- slice_sample(sm_df, n = 8000L)
  }
  pc <- ggplot(sm_df, aes(x = epic_managed_grass_ha + 1, y = lum_area_ha + 1, colour = region)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey35") +
    geom_point(alpha = 0.25, size = 0.9) +
    scale_x_log10(labels = scales::comma) + scale_y_log10(labels = scales::comma) +
    labs(title = "C. SimUID Pasture Area vs EPIC Reference Table", x = "EPIC GRS_LUM_AreaHa X15..25 (ha + 1)", y = "Hosted LUM COG 15..25 (ha + 1)", colour = "Country") +
    theme_bw(base_size = 9.5) + theme(legend.position = "bottom")

  unf_df <- perf$unfccc_by_species %>%
    as_tibble() %>%
    filter(!is.na(CH4_ent_unfccc_kt))
  pd <- ggplot(unf_df, aes(x = CH4_ent_unfccc_kt, y = CH4_ent_tier1_kt, colour = species, shape = region)) +
    geom_abline(slope = 1, intercept = 0, linetype = "dashed", colour = "grey35") +
    geom_point(size = 2.8) +
    labs(title = "D. Enteric CH4: FAOSTAT Tier 1 vs UNFCCC NIR", x = "UNFCCC Inventory (kt CH4)", y = "Downscaled FAOSTAT Tier 1 (kt CH4)", colour = "Species", shape = "Country") +
    theme_bw(base_size = 9.5) + theme(legend.position = "bottom")

  p_perf <- (pa | pb) / (pc | pd) +
    plot_annotation(
      title = sprintf("Non-Self-Contained Performance Benchmarks — run %s", PASTURE_RESULT_TAG),
      theme = theme(plot.title = element_text(face = "bold", size = 12))
    )
  ggsave(file.path(plot_dir, "pasture_independent_performance.png"), p_perf, width = 13.5, height = 10, dpi = 220, bg = "white")
}

message("  [P14] Saved independent performance & benchmark plots to ", plot_dir)
