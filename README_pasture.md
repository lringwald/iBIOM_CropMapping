# Pasture & Ruminant Livestock Disaggregation Module (`pasture_livestock`)

Self-contained, non-GLOBIOM spatial downscaling pipeline for European pasture productivity, ruminant livestock populations, milk/meat production, nitrogen flows, and livestock + pasture soil GHG emissions at **1 km² EEA resolution (`EPSG:3035`, `CELLCODE`)** and **EPIC Simulation Unit (`SimUID`)** level.

---

## 1. Architecture Overview

The module shares the LAMASUS 100 m Land Use and Management (`LUM`) raster and 1 km EEA master grid mapping from `iBIOM_CropMapping`, while replacing GLOBIOM regional targets and feed coefficients with consistent national accounting from **FAOSTAT (`QCL`, `GLE`, `EMN`, `EK`)** and spatial species/productivity priors from **Eurostat (`ef_lsk_bovine`, `ef_lsk_sheep`, `ef_lsk_goats`, `agr_r_milkpr`)** plus an external EW-MFA benchmark (`env_ac_mfa`).

All inputs resolve across multi-root paths without hardcoded user-machine directories: `LUM` rasters resolve across `/mnt/wdrv/iBIOM_Explorer/Land_use_and_management` (WKUBE container), `~/accelerator/mnt/ibiom/iBIOM_Explorer/Land_use_and_management` (`accli mount start ibiom`), and local `input/LUM_data/`; non-LUM prepared `.rds` files resolve across local `input/` and `SHARED_INPUT_DIR` (`/mnt/wdrv/Data/preprocessed_data/iBIOM_CropMapping_input`). Detailed raw file provenance is recorded in [`SOURCES.md`](SOURCES.md), and traced execution lineage is documented in [`PIPELINE_LINEAGE.md`](PIPELINE_LINEAGE.md).

### Four Ruminant Species

1. `dairy_cattle`
2. `non_dairy_cattle`
3. `sheep`
4. `goats`

### LAMASUS Grassland & Pasture Classes (`lum_grass_classes.csv`)

The pipeline filters `LUM_<year>.tif` to `lum_grass_map <- 15:25` (excluding `26`, unmanaged semi-natural/natural grassland):

| `LUM.class` | Description | Grazing Mode | Synthetic Mineral N Allowed |
| :---: | :--- | :--- | :---: |
| `15` | Very high density managed pasture system | `direct_pasture` | `TRUE` |
| `16` | High density managed pasture system | `direct_pasture` | `TRUE` |
| `17` | Moderate density managed pasture system | `direct_pasture` | `TRUE` |
| `18` | Low density managed pasture system | `direct_pasture` | `TRUE` |
| `19` | Very high density managed grassland | `mown_grassland` | `TRUE` |
| `20` | High density managed grassland | `mown_grassland` | `TRUE` |
| `21` | Moderate density managed grassland | `mown_grassland` | `TRUE` |
| `22` | Low density managed grassland | `mown_grassland` | `TRUE` |
| `23` | Rough grazing | `direct_pasture` | `FALSE` |
| `24` | Silvo-pastoral agroforestry | `direct_pasture` | `FALSE` |
| `25` | Managed semi-natural and natural grassland | `direct_pasture` | `FALSE` |

---

## 2. Mathematical Methodology

### 2.1 Pasture Area & Forage Biomass (`P05`, `P07`)

Each 100 m LUM pixel ($1\ \text{ha} = 0.01\ \text{km}^2$) inside `lum_grass_map` is assigned to its 1 km EEA `CELLCODE` (`EOFORIGIN`, `NOFORIGIN` in `EPSG:3035`), preserving exact class areas $A_{i,m}$ at `(CELLCODE, LUM.class)`.

Joining EPIC-IIASA Grassland parameters by `(SimUID, LUM.class)` yields cell-class annual forage dry-matter production:

$$B_{i,m} = A_{i,m} \cdot \text{YLDF}_{i,m} \quad [\text{t DM yr}^{-1}]$$

Any `(SimUID, LUM.class)` missing an exact EPIC record is logged in `fallbacks_log.csv` (`epic_missing_simuid`) and filled from the country `LUM.class` area-weighted mean (with EU mean fallback if needed).

### 2.2 Endogenous Country Grazing Feed Coefficient & 2D IPF Disaggregation (`P09`)

Let $B_c = \sum_{i,m} B_{i,m}$ be total country forage DM from EPIC across `LUM 15..25`, and $\text{LSU}_c = \sum_{k=1}^{4} \text{LSU}_{c,k}$ be total national ruminant Livestock Units from FAOSTAT `EK` + `GLE` (`dairy_cattle = 1.0`, `sheep = 0.1`, `goats = 0.1`, `non_dairy_cattle` solved exactly as residual cattle LSU per non-dairy head).

1. **Endogenous country grazing feed coefficient:**
   $$\gamma_c = \frac{B_c}{\text{LSU}_c} \quad [\text{t DM LSU}^{-1}\text{ yr}^{-1}]$$
2. **Sustainable row carrying capacity:**
   $$\text{LSU}_{i,m} = \frac{B_{i,m}}{\gamma_c}$$
3. **2D Iterative Proportional Fitting strictly via `cascadecore::fienberg()` (`solve_ipf_2d`):**
   Allocated species Livestock Units $L_{i,m,k}$ solve the biproportional scaling problem (`tol.margin = 1e-9`, `tol.optim = 1e-12`, `tol.gain = 1e-14`, `max.iter = 500`) matching $\sum_k L_{i,m,k} = \text{LSU}_{i,m}$ and $\sum_{i,m} L_{i,m,k} = \text{LSU}_{c,k}$ by delegating directly to `cascadecore::fienberg()` loaded canonically from vendored `external/cascade-core` (via `ensure_cascade_engine()`, overrideable via `CASCADE_CORE_PATH`). Starting shares `S0` apply a floor `MIN_EXP = 1e-12` on active cells, row-normalize active rows, and are seeded from Eurostat NUTS2 livestock species shares (`ef_lsk_bovine`, `ef_lsk_sheep`, `ef_lsk_goats`, weighted by national `lsu_per_head`) when `USE_EUROSTAT_PRIORS = TRUE`, with explicit fallback to national FAOSTAT species shares on border/unmapped cells.
4. **Head conversion & external benchmark:**
   Heads $H_{i,m,k} = L_{i,m,k} / \text{lsu\_per\_head}_{c,k}$ conserve FAOSTAT `GLE` national stocks. The endogenous $\gamma_c$ is compared directly against Eurostat EW-MFA grazed biomass (`env_ac_mfa` `MF1222`, converted via $0.85$ dry-matter factor at 15% moisture divided by $\text{LSU}_c$).

### 2.3 Milk & Carcass Meat Production (`P10`)

* **Meat (`t` carcass weight):** Disaggregated proportionally to heads using FAOSTAT `QCL` species carcass meat per head (`meat_t_head`).
* **Milk (`t` raw milk):** When `USE_EUROSTAT_PRIORS = TRUE`, `dairy_cattle` yield per cow is spatially modulated across NUTS2 regions using Eurostat `agr_r_milkpr / ef_lsk_bovine` normalized around the national weighted mean, then multiplied by an exact species reconciliation factor so national sums match FAOSTAT `QCL` 100%.

### 2.4 Livestock & Pasture Soil GHG Budget Without Double Counting (`P11`)

* **Livestock emissions & N flows (species level):** Computed strictly per head from FAOSTAT `GLE` (`CH4_enteric`, `CH4_manure_mgt`, direct/indirect `N2O_manure_mgt`, `N2O_pasture_prp`, `N2O_manure_applied`; both `FAO TIER 1` and `UNFCCC` stored) and `EMN` (`N_excreted`, `N_left_on_pasture`, `N_treated_mms`, `N_applied_soils`).
* **Land/soil fluxes (zero species multiplication):** Computed strictly **once per `(CELLCODE, LUM.class)`** on `temp.pasture` before joining `lsk_lum` (`1:1`):
  * Soil organic carbon CO2 flux: $\text{CO}_{2,\text{SOC},i,m} = -\text{dOCPD}_{i,m} \cdot A_{i,m} \cdot \frac{44}{12}$.
  * Synthetic mineral fertilizer $\text{N}_2\text{O}$: Raw EPIC `NFERT` combines mineral + organic N and is invariant across `LUM 15..26`; `prep_EPIC_grass.R` estimates organic N from manure C input ($\text{FCO}/12$), isolates residual synthetic mineral N on `LUM 15..22` (`0` on `LUM 23..25`), and applies IPCC 2019 Tier 1 default factors (`EF1 = 0.010`, `Frac_GASF = 0.11`, `EF4 = 0.010`, `Frac_LEACH = 0.24`, `EF5 = 0.011`, `N2O_N_to_N2O = 44/28`). Raw `NFERT` $\text{N}_2\text{O}$ is retained solely as `N2O_epic_raw_nfert_diag_t` for transparency.

---

## 3. Referenced Constants (`codes/support/pasture_params/pasture_reference_constants.csv`)

| Parameter | Value | Unit | Reference |
| :--- | :---: | :--- | :--- |
| `C_to_CO2` | `3.6666667` | `t CO2 / t C` | IUPAC exact `44/12` stoichiometry |
| `N2O_N_to_N2O` | `1.5714286` | `t N2O / t N2O-N` | IPCC 2019 Vol. 4 Ch. 11 (`44/28`) |
| `GWP_CH4_AR6` / `GWP_N2O_AR6` | `27` / `273` | `t CO2e / t` | IPCC AR6 WG1 Table 7.15 (non-fossil CH4, 100-yr) |
| `GWP_CH4_AR5` / `GWP_N2O_AR5` | `28` / `265` | `t CO2e / t` | IPCC AR5 WG1 Table 8.A.1 |
| `GWP_CH4_AR4` / `GWP_N2O_AR4` | `25` / `298` | `t CO2e / t` | IPCC AR4 WG1 Table 2.14 |
| `EF1_synth_ipcc2019` | `0.010` | `kg N2O-N / kg N` | IPCC 2019 Vol. 4 Ch. 11 Table 11.1 |
| `Frac_GASF_ipcc2019` / `EF4_volat_ipcc2019` | `0.11` / `0.010` | `-` / `kg N2O-N / kg N` | IPCC 2019 Vol. 4 Ch. 11 Table 11.3 |
| `Frac_LEACH_ipcc2019` / `EF5_leach_ipcc2019` | `0.24` / `0.011` | `-` / `kg N2O-N / kg N` | IPCC 2019 Vol. 4 Ch. 11 Table 11.3 |
| `manure_CN_ratio_default` | `12.0` | `kg C / kg N` | Standard manure C:N ratio (`FCO / 12`) |
| `mfa_15pct_moisture_to_dm` | `0.85` | `t DM / t EW-MFA` | Eurostat EW-MFA Compilation Guide (2018) |

---

## 4. Configuration & Running

1. Copy [`user_config_TEMPLATE.R`](user_config_TEMPLATE.R) to `user_config.R` and configure:
   * `INPUT_DIR <- "input"`
   * `PASTURE_RESULT_TAG <- "pasture_v1"`
   * `PASTURE_RUN_YEARS <- "2018"` (supports `2000`, `2010`, `2018`)
   * `PASTURE_COUNTRIES <- c("AT", "NL", "ES")` (set to `NULL` to run all mapped EU countries except `CY`, which has `0` 1 km pixels)
   * `FAOSTAT_EMISSION_SOURCE`: `"FAO TIER 1"` (or `"UNFCCC"`)
   * `USE_EUROSTAT_PRIORS`: `TRUE` (or `FALSE` for uniform national species/yield baseline)
   * `GWP_VERSION`: `"AR6"` (`"AR5"`, `"AR4"`)
2. Verify R packages, GDAL drivers (`GPKG`, `COG`, `arrow`), and local paths:
   ```bash
   Rscript codes/pasture/P00_check_env.R
   ```
3. Run the complete pipeline:
   ```bash
   Rscript main_pasture.R
   ```
4. Regenerate plots/reports standalone from completed aggregated outputs:
   ```bash
   Rscript -e 'source("user_config.R"); source("codes/pasture/P14_plot_results.R")'
   Rscript codes/pasture/P16_run_report.R
   ```

---

## 5. Output Directory Layout (`output/<PASTURE_RESULT_TAG>/`)

* `output/<tag>/pasture_band_catalogue.csv`: Distributable 24-band metadata legend (`variable_type`, `value_semantics`, `unit`, `datatype`, `nodata`).
* `output/<tag>/<REG>_<YEAR>_<tag>.rds`: Full atomic country bundle (`cell_summary`, `lum_summary`, `species_lum_alloc`, `species_summary`, `country_summary`, `nuts2_summary`, `lum_source`, `ledger`, `fallbacks`).
* `output/<tag>/country_res/` (every binary output carries a `<file>.json` sidecar):
  * `<tag>_pasture_<REG>_<YEAR>.tif`: 24-band `EPSG:3035` 1 km `FLT4S` Cloud-Optimized GeoTIFF (`NAflag = -9999`, `COMPRESS=DEFLATE`, verified against `cell_summary` to `< 1e-4` relative error on all extensive bands).
  * `<tag>_pasture_<REG>_<YEAR>.gpkg`: `EPSG:3035` 1 km cell centroid vector layer.
  * `<tag>_pasture_<REG>_<YEAR>.parquet`: Canonical tabular Apache Parquet table (`arrow`).
* `output/<tag>/aggregated/`: Combined `<tag>_pasture.rds` plus 6 canonical Parquet tables (`cell_all`, `lum_all`, `species_alloc`, `species_summary`, `country_summary`, `nuts2_summary`) and JSON sidecars.
* `output/<tag>/simu_res/`: `SimUID x LUM.class` (`simu_lum`) and `SimUID` (`simu_total`) conservation-checked aggregations in `.rds`, `.parquet`, and `.parquet.json`.
* `output/<tag>/report/`: `performance_summary.rds`, 6 non-self-contained benchmark tables (`performance_*.{csv,parquet,parquet.json}`), `report_objects.rds`, CSV audit tables (`country_summary.csv`, `species_targets_fulfilment.csv`, `conservation_ledger.csv`, `fallbacks_log.csv`), 5 report PNGs (`fig/`), `<tag>_run_report.md`, and self-contained `<tag>_run_report.html`.
* `output/<tag>/run_manifest.rds` & `run_manifest.json`: Run provenance, git metadata, hosted `lum_files`, config, and input MD5 checksums.

---

## 6. IIASA Accelerator WKUBE Routine (`ibiom`)

The repository is packaged as an Accelerator WKUBE routine (`Dockerfile`, `init.R`, `entrypoint.sh`, `config/knobs.json`, `docs/routine_config.schema.json`, `wkube.py`):

1. **Regenerate schema & build ID after knob/code changes:**
   ```bash
   Rscript tools/gen_config.R
   sh tools/build_id.sh . > .build_id
   ```
2. **Stage canonical Parquet/RDS inputs AND raw EPIC/FAOSTAT sources onto `/mnt/wdrv` via `accli mount`:**
   ```bash
   accli mount start ibiom
   bash tools/stage_wkube_inputs.sh
   ```
   Or process raw EPIC Grassland files standalone anytime via:
   ```bash
   Rscript codes/support/prep_EPIC_grass.R
   ```
3. **Run via `entrypoint.sh` locally or inspect `wkube.py` routines (`check`, `trial`, `pasture_2018`, `pasture_all_years`, `cropland`, `all`):**
   ```bash
   TASK=trial bash entrypoint.sh
   ```
   Inside WKUBE containers, `entrypoint.sh` maps `/mnt/wdrv/iBIOM_Explorer/Land_use_and_management/<year>/ibiom_LUM_europe_100m_<year>.tif` automatically and symlinks `output/` onto a per-routine `$WORK_DIR/output` directory so the cluster uploader collects all artifacts.

