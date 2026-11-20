##### PASTURE P10: milk & meat production reconciled 100% to FAOSTAT QCL targets
##### Optional Eurostat NUTS2 cow milk yield prior (agr_r_milkpr / ef_lsk_bovine)

alloc.sp <- merge(
  alloc.sp,
  curr.accounts[, .(species, milk_t_target = milk_t, meat_t_target = meat_t, milk_t_head, meat_t_head)],
  by = "species",
  all.x = TRUE
)

## Meat production (t carcass weight) from FAOSTAT per-head yield
alloc.sp[, meat_t := fifelse(!is.na(meat_t_head), heads * meat_t_head, 0)]

## Milk production (t raw milk): uniform FAOSTAT per-head yield by default,
## modulated across NUTS2 regions by Eurostat agr_r_milkpr / ef_lsk_bovine for dairy_cattle when available
alloc.sp[, milk_yield_idx := 1.0]

if (isTRUE(USE_EUROSTAT_PRIORS) && nrow(curr.eurostat_milk) > 0L && nrow(curr.eurostat_lsk) > 0L) {
  dc_lsk <- curr.eurostat_lsk[species == "dairy_cattle" & substr(NUTS2, 1L, 2L) == lama.reg,
                              .(NUTS2, heads_fss)]
  dc_mk  <- curr.eurostat_milk[substr(NUTS2, 1L, 2L) == lama.reg, .(NUTS2, milk_cow_t_eurostat)]
  dc_reg <- merge(dc_lsk, dc_mk, by = "NUTS2", all = FALSE)
  dc_reg <- dc_reg[!is.na(heads_fss) & heads_fss > 0 & !is.na(milk_cow_t_eurostat) & milk_cow_t_eurostat > 0]

  if (nrow(dc_reg) > 0L) {
    dc_reg[, yld_raw := milk_cow_t_eurostat / heads_fss]
    mean_yld <- stats::weighted.mean(dc_reg$yld_raw, dc_reg$heads_fss)
    if (!is.na(mean_yld) && mean_yld > 0) {
      dc_reg[, idx := yld_raw / mean_yld]
      alloc.sp <- merge(
        alloc.sp,
        dc_reg[, .(NUTS2, idx)],
        by = "NUTS2", all.x = TRUE
      )
      alloc.sp[species == "dairy_cattle" & !is.na(idx), milk_yield_idx := idx]
      alloc.sp[, idx := NULL]
    }
  }
}

alloc.sp[, milk_t_unscaled := fifelse(!is.na(milk_t_head), heads * milk_t_head * milk_yield_idx, 0)]

## Exact reconciliation factor per species so sum(milk_t) == FAOSTAT QCL milk_t_target
milk_scale_dt <- alloc.sp[, .(
  milk_raw = sum(milk_t_unscaled),
  milk_tgt = milk_t_target[1L]
), by = species]
milk_scale_dt[, milk_shifter := fifelse(!is.na(milk_tgt) & milk_raw > 0, milk_tgt / milk_raw, 1.0)]

alloc.sp <- merge(alloc.sp, milk_scale_dt[, .(species, milk_shifter)], by = "species", all.x = TRUE)
alloc.sp[, milk_t := milk_t_unscaled * milk_shifter]
alloc.sp[, c("milk_t_unscaled", "milk_shifter", "milk_yield_idx", "milk_t_target", "meat_t_target", "milk_t_head", "meat_t_head") := NULL]

assert_contract(
  alloc.sp, sprintf("P10/%s_%s/alloc.sp", lama.reg, curr.year),
  req_cols = c("CELLCODE", "LUM.class", "species", "LSU", "heads", "milk_t", "meat_t"),
  key_cols = c("CELLCODE", "LUM.class", "species"),
  non_neg_cols = c("LSU", "heads", "milk_t", "meat_t")
)

## Conservation checks for milk and meat per species
prod_chk <- merge(
  alloc.sp[, .(milk_alloc = sum(milk_t), meat_alloc = sum(meat_t)), by = species],
  curr.accounts[, .(species, milk_target = milk_t, meat_target = meat_t)],
  by = "species"
)
for (i in seq_len(nrow(prod_chk))) {
  r <- prod_chk[i]
  if (!is.na(r$milk_target) && r$milk_target > 0) {
    rel <- abs(r$milk_alloc - r$milk_target) / r$milk_target
    if (rel > 1e-4) stop(sprintf("[P10] Milk conservation failed for %s (%s): rel=%.3e", lama.reg, r$species, rel))
    curr.ledger[[length(curr.ledger) + 1L]] <- new_ledger_entry(
      "P10_production", lama.reg, curr.year, paste0("milk_t_", r$species), "t", r$milk_alloc, r$milk_target
    )
  }
  if (!is.na(r$meat_target) && r$meat_target > 0) {
    rel <- abs(r$meat_alloc - r$meat_target) / r$meat_target
    if (rel > 1e-4) stop(sprintf("[P10] Meat conservation failed for %s (%s): rel=%.3e", lama.reg, r$species, rel))
    curr.ledger[[length(curr.ledger) + 1L]] <- new_ledger_entry(
      "P10_production", lama.reg, curr.year, paste0("meat_t_", r$species), "t", r$meat_alloc, r$meat_target
    )
  }
}

message(sprintf("  [P10] Reconciled milk = %.0f t, meat = %.0f t.", sum(alloc.sp$milk_t), sum(alloc.sp$meat_t)))

