##### PASTURE P02: prepare required inputs if missing or listed in FORCE_PREP
##### Canonical tabular outputs are stored as Apache Parquet (.parquet) alongside .rds.

if (!exists("FORCE_PREP")) FORCE_PREP <- character()

## Offline helper: if eurostat_priors_nuts2.rds already exists locally (and not forced),
## materialize its canonical .parquet tables without requiring live Eurostat API network calls.
if (file.exists(eurostat.priors.path) &&
    !"eurostat_priors" %in% FORCE_PREP &&
    !all(file.exists(c(eurostat.priors.lsk.pq.path, eurostat.priors.milk.pq.path, eurostat.priors.mfa.pq.path)))) {
  ep_cached <- readRDS(eurostat.priors.path)
  save_parquet_atomic(ep_cached$nuts2_livestock, eurostat.priors.lsk.pq.path)
  save_parquet_atomic(ep_cached$nuts2_milk, eurostat.priors.milk.pq.path)
  save_parquet_atomic(ep_cached$nat_mfa, eurostat.priors.mfa.pq.path)
  write_output_sidecar(eurostat.priors.lsk.pq.path, "eurostat_priors_nuts2_livestock", "cached_rds_sync")
  write_output_sidecar(eurostat.priors.milk.pq.path, "eurostat_priors_nuts2_milk", "cached_rds_sync")
  write_output_sidecar(eurostat.priors.mfa.pq.path, "eurostat_priors_nat_mfa", "cached_rds_sync")
  rm(ep_cached)
}

pasture_prep_steps <- list(
  list(
    name   = "country_grid",
    script = "prep_country_grid.R",
    out    = country.grid.path
  ),
  list(
    name   = "EPIC_grass",
    script = "prep_EPIC_grass.R",
    out    = c(EPIC.grass.path, EPIC.grass.pq.path, EPIC.grass.ref.path, EPIC.grass.ref.pq.path)
  ),
  list(
    name   = "faostat_accounts",
    script = "prep_faostat_accounts.R",
    out    = c(faostat.accounts.path, faostat.accounts.pq.path)
  ),
  list(
    name   = "eurostat_priors",
    script = "prep_eurostat_priors.R",
    out    = c(eurostat.priors.path, eurostat.priors.lsk.pq.path, eurostat.priors.milk.pq.path, eurostat.priors.mfa.pq.path)
  )
)

for (step in pasture_prep_steps) {
  if (all(file.exists(step$out)) && !step$name %in% FORCE_PREP) next

  message(sprintf("▶ PREPARING %s (support/%s)...", step$name, step$script))
  source(file.path("./codes/support", step$script), local = new.env(parent = globalenv()))
  gc()

  if (!all(file.exists(step$out))) {
    stop("Preparation step '", step$name, "' did not create: ",
         paste(step$out[!file.exists(step$out)], collapse = ", "))
  }
}
