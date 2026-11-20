##### PASTURE P09: endogenous grazing feed coefficient & 2D IPF livestock disaggregation
##### - Grazing feed coefficient gamma_c = sum(forage_dm_t) / sum(FAOSTAT_LSU_c) [t DM / LSU / yr]
##### - Pixel x LUM carrying capacity LSU_im = forage_dm_t / gamma_c
##### - Species disaggregation via 2D IPF with Eurostat NUTS2 species priors (ef_lsk_*)

sp_order <- c("dairy_cattle", "non_dairy_cattle", "sheep", "goats")
acc_ord <- curr.accounts[match(sp_order, species)]
if (any(is.na(acc_ord$species))) {
  stop(sprintf("[P09] Missing species in curr.accounts for %s %s.", lama.reg, curr.year))
}

total_forage_dm_t <- sum(temp.pasture$forage_dm_t)
total_lsu_target  <- sum(acc_ord$lsu)
if (total_forage_dm_t <= 0 || total_lsu_target <= 0) {
  stop(sprintf("[P09] Non-positive forage (%.2f) or LSU target (%.2f) in %s %s.",
               total_forage_dm_t, total_lsu_target, lama.reg, curr.year))
}

## Endogenous country grazing feed coefficient (t DM forage per FAOSTAT LSU per year)
grazing_feed_coef_t_dm_lsu <- total_forage_dm_t / total_lsu_target

temp.pasture[, `:=`(
  grazing_feed_coef_t_dm_lsu = grazing_feed_coef_t_dm_lsu,
  LSU_total = forage_dm_t / grazing_feed_coef_t_dm_lsu
)]

## Construct prior share matrix (n_rows x 4 species)
nat_lsu_shares <- acc_ord$lsu / total_lsu_target
names(nat_lsu_shares) <- sp_order

seed_mat <- matrix(
  rep(nat_lsu_shares, each = nrow(temp.pasture)),
  nrow = nrow(temp.pasture), ncol = length(sp_order),
  dimnames = list(NULL, sp_order)
)

eurostat_lsk_cov_share <- 0
if (isTRUE(USE_EUROSTAT_PRIORS) && nrow(curr.eurostat_lsk) > 0L) {
  ## Regional Eurostat prior LSU per NUTS2 x species using FAOSTAT lsu_per_head
  pr <- merge(
    curr.eurostat_lsk[substr(NUTS2, 1L, 2L) == lama.reg],
    acc_ord[, .(species, lsu_per_head)],
    by = "species", all.x = TRUE
  )
  pr[, prior_lsu := heads_fss * lsu_per_head]
  pr_w <- dcast(pr, NUTS2 ~ species, value.var = "prior_lsu", fun.aggregate = sum, na.rm = TRUE)
  for (sp in sp_order) {
    if (!sp %in% names(pr_w)) pr_w[, (sp) := 0]
  }
  pr_w[, tot_pr := rowSums(.SD), .SDcols = sp_order]
  pr_w <- pr_w[tot_pr > 0]

  if (nrow(pr_w) > 0L) {
    for (sp in sp_order) {
      ## Where a NUTS2 region reports 0 or missing, keep small national fallback floor only if tot_pr > 0;
      ## actually convert NUTS2 prior_lsu to shares directly (0 stays 0, handled safely by IPF floor LOG_P_MIN)
      pr_w[, (sp) := get(sp) / tot_pr]
    }
    row_nuts <- data.table(row_id = seq_len(nrow(temp.pasture)), NUTS2 = temp.pasture$NUTS2)
    row_pr <- merge(row_nuts, pr_w[, c("NUTS2", sp_order), with = FALSE], by = "NUTS2", all.x = TRUE, sort = FALSE)
    setorder(row_pr, row_id)

    matched_rows <- !is.na(row_pr[[sp_order[1L]]])
    eurostat_lsk_cov_share <- sum(temp.pasture$forage_dm_t[matched_rows]) / total_forage_dm_t

    if (any(matched_rows)) {
      for (sp in sp_order) {
        vals <- row_pr[[sp]]
        seed_mat[matched_rows, sp] <- vals[matched_rows]
      }
    }
    if (eurostat_lsk_cov_share < 1 - 1e-6) {
      curr.fallbacks[[length(curr.fallbacks) + 1L]] <- new_fallback_entry(
        stage = "P09_disaggregation", region = lama.reg, year = curr.year,
        kind = "eurostat_nuts2_prior_partial",
        requested = "100% forage coverage of Eurostat NUTS2 livestock prior",
        used = sprintf("%.2f%% matched; remainder uses national FAOSTAT species shares", 100 * eurostat_lsk_cov_share),
        affected_share = 1 - eurostat_lsk_cov_share,
        reason = "Border or unmapped NUTS2 cells absent from Eurostat FSS NUTS2 table"
      )
    }
  }
} else {
  curr.fallbacks[[length(curr.fallbacks) + 1L]] <- new_fallback_entry(
    stage = "P09_disaggregation", region = lama.reg, year = curr.year,
    kind = "eurostat_nuts2_prior_absent",
    requested = "Eurostat NUTS2 ef_lsk_* prior",
    used = "national FAOSTAT species shares across all pixels",
    affected_share = 1.0,
    reason = ifelse(isTRUE(USE_EUROSTAT_PRIORS), "No Eurostat NUTS2 rows available", "USE_EUROSTAT_PRIORS = FALSE")
  )
}

## Solve 2D IPF: rowSums(X) == temp.pasture$LSU_total, colSums(X) == acc_ord$lsu
ipf_res <- solve_ipf_2d(
  seed_mat    = seed_mat,
  row_targets = temp.pasture$LSU_total,
  col_targets = acc_ord$lsu,
  rel_tol     = 1e-9,
  max_iter    = 500L
)
prior_kl_div <- compute_kl_divergence(ipf_res$alloc, seed_mat, temp.pasture$forage_dm_t)

## Build long species x CELLCODE x LUM.class allocation table
alloc_list <- vector("list", length(sp_order))
for (j in seq_along(sp_order)) {
  sp <- sp_order[j]
  w_lsu <- acc_ord$lsu_per_head[j]
  lsu_vec <- ipf_res$alloc[, j]
  heads_vec <- if (!is.na(w_lsu) && w_lsu > 0) lsu_vec / w_lsu else rep(0, length(lsu_vec))
  alloc_list[[j]] <- data.table(
    CELLCODE  = temp.pasture$CELLCODE,
    EOFORIGIN = temp.pasture$EOFORIGIN,
    NOFORIGIN = temp.pasture$NOFORIGIN,
    SimUID    = temp.pasture$SimUID,
    NUTS2     = temp.pasture$NUTS2,
    LUM.class = temp.pasture$LUM.class,
    species   = sp,
    LSU       = lsu_vec,
    heads     = heads_vec
  )
}
alloc.sp <- rbindlist(alloc_list)

assert_contract(
  alloc.sp, sprintf("P09/%s_%s/alloc.sp", lama.reg, curr.year),
  req_cols = c("CELLCODE", "LUM.class", "species", "LSU", "heads"),
  key_cols = c("CELLCODE", "LUM.class", "species"),
  non_neg_cols = c("LSU", "heads")
)

## Reconcile conservation ledger per species
for (j in seq_along(sp_order)) {
  sp <- sp_order[j]
  sub_sp <- alloc.sp[species == sp]
  curr.ledger[[length(curr.ledger) + 1L]] <- new_ledger_entry(
    "P09_disaggregation", lama.reg, curr.year,
    paste0("LSU_", sp), "LSU", sum(sub_sp$LSU), acc_ord$lsu[j],
    sprintf("IPF %s (%d iters)", ipf_res$stop_reason, ipf_res$iterations)
  )
  curr.ledger[[length(curr.ledger) + 1L]] <- new_ledger_entry(
    "P09_disaggregation", lama.reg, curr.year,
    paste0("heads_", sp), "heads", sum(sub_sp$heads), acc_ord$heads[j],
    "Converted via FAOSTAT EK lsu_per_head"
  )
  rel_h <- if (acc_ord$heads[j] > 0) abs(sum(sub_sp$heads) - acc_ord$heads[j]) / acc_ord$heads[j] else 0
  if (rel_h > 1e-4) {
    stop(sprintf("[P09] Head conservation failed for %s %s (%s): rel diff = %.4e",
                 lama.reg, curr.year, sp, rel_h))
  }
}

message(sprintf("  [P09] Grazing coef gamma_c = %.3f t DM/LSU/yr | IPF %s (%d iters) | NUTS2 prior cov = %.1f%%",
                grazing_feed_coef_t_dm_lsu, ipf_res$stop_reason, ipf_res$iterations,
                100 * eurostat_lsk_cov_share))

