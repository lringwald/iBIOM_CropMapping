# Pipeline Lineage (`PIPELINE_LINEAGE.md`)

Provenance and execution lineage for the Pasture & Ruminant Livestock downscaling pipeline (`pasture_livestock` branch), traced directly from the run manifest (`output/pasture_v1/run_manifest.json`), provenance registry (`SOURCES.md`), conservation ledger (`output/pasture_v1/report/conservation_ledger.csv`), fallbacks log (`output/pasture_v1/report/fallbacks_log.csv`), and verified summary outputs.

---

## 1. Execution Provenance

| Field | Traced Value |
| :--- | :--- |
| **Run ID (`PASTURE_RESULT_TAG`)** | `pasture_v1` (via `TASK=trial bash entrypoint.sh`, clean fresh `output/pasture_v1/`) |
| **Git Branch / Commit** | `pasture_livestock` / `b07dcc5f22cb2749a4f3674ffcfde946f26193f8` (`git_dirty: true`) |
| **Full Pipeline Run Window** | `2026-11-20T20:28:08Z` to `2026-11-20T20:34:14Z` |
| **Hosted LUM Layer (`lum_files`)** | `/Users/leopoldringwald/accelerator/mnt/ibiom/iBIOM_Explorer/Land_use_and_management/2018/ibiom_LUM_europe_100m_2018.tif` (`192M` BigTIFF COG, resolved across `accli` mount `ibiom`; WKUBE container resolves `/mnt/wdrv/iBIOM_Explorer/Land_use_and_management`) |
| **IPF Solver Engine (`engine_cascade_core`)** | `cascadecore` `v0.1.0` (`vendored external/cascade-core`: `/Users/leopoldringwald/Library/CloudStorage/GoogleDrive-leopold.ringwald@gmail.com/My Drive/R/iBIOM_CropMapping/external/cascade-core`, `commit`: `null` / vendored checkout, `cascadecore::fienberg`) |
| **Host / R Runtime** | `Leopolds-MacBook-Pro.local` / `R version 4.4.1 (2024-06-14)` |
| **Package Versions** | `terra 1.7.78`, `sf 1.0.17`, `data.table 1.18.0`, `eurostat 4.0.0`, `arrow 22.0.0.1`, `devtools 2.4.5`, `nloptr 2.1.1`, `matrixStats 1.5.0`, `cli 3.6.5` |
| **Configured Scope** | `PASTURE_RUN_YEARS = "2018"`, `PASTURE_COUNTRIES = c("AT", "NL", "ES")`, `lum_grass_map = 15:25` |
| **Model Switches** | `LIVESTOCK_ACCOUNTING_SOURCE = "faostat"`, `FAOSTAT_EMISSION_SOURCE = "FAO TIER 1"`, `USE_EUROSTAT_PRIORS = TRUE`, `GWP_VERSION = "AR6"` (`CH4 = 27`, `N2O = 273`), `EXPORT_PASTURE_SPATIAL = TRUE` |

---

## 2. Exact Input Artifacts & Checksums

### 2.1 Staged Canonical Parquet & Config Inputs Registered in `run_manifest.json`

| Path | MD5 Checksum | Key Size / Content (Observed) |
| :--- | :--- | :--- |
| `input/EPIC/EPIC_grass_params.parquet` | `237db39dcb9a3be813cdb64da6c77710` | `4,234,140` `SimUID x LUM.class` rows (`29M`, + `.parquet.json` sidecar) |
| `input/EPIC/EPIC_grass_simu_ref.parquet` | `58c21a9a76fdb4df8e0a9747e86258f2` | `352,845` `SimUID` raw `REF` + `GRS_LUM_AreaHa_BySimUID` benchmark rows (`18M`) |
| `input/targets/pasture/faostat_national_accounts.parquet` | `2295e91c0f053583ac521df9d881a391` | `756` `(region x year x species)` rows across `27` countries (`205K`) |
| `input/targets/pasture/eurostat_priors_nuts2_livestock.parquet` | `6b32a74e8aee8208790ff6a53255de31` | `3,102` Eurostat FSS NUTS2 livestock rows |
| `input/targets/pasture/eurostat_priors_nuts2_milk.parquet` | `9fa9e004b8988dde64dc1729c1769a1b` | `1,062` Eurostat `agr_r_milkpr` NUTS2 milk rows |
| `input/targets/pasture/eurostat_priors_nat_mfa.parquet` | `96d00fcae9828d7756e4a01b6aeae6d6` | `81` Eurostat EW-MFA `MF1221/MF1222` national benchmark rows |
| `input/mappings/one_km_to_lower_resolution_mapping_NUTS_2016_imputed.rds` | `b313ede6d8c2c6a21a0f1b9f52f80aae` | `4,927,404` unique 1 km `CELLCODE` pixels (`EPSG:3035`) |
| `codes/support/pasture_params/pasture_reference_constants.csv` | `a1b8f4155d381e0a24fef2bd62a4aca4` | `18` referenced IPCC/Eurostat/stoichiometric constants |
| `codes/support/pasture_params/lum_grass_classes.csv` | `d2a1b60c343e5b49c652a3ff4074e9d4` | `12` LAMASUS grassland classes (`15..26`) with grazing mode and synthetic N flag |
| `codes/support/pasture_params/pasture_band_catalogue.csv` | `ee9cde50b336016a222f6cf49c2f67a5` | `24` COG band definitions (`variable_type`, `value_semantics`, `FLT4S`, `NA=-9999`) |

### 2.2 Raw & Hosted Source Files (`SOURCES.md`)

* Hosted COG `iBIOM_Explorer/Land_use_and_management/2018/ibiom_LUM_europe_100m_2018.tif` (`192M` BigTIFF, LAMASUS v1.0.0, `DOI: 10.5281/zenodo.21787459`)
* Fallback local `input/LUM_data/LUM_2018.tif`: `101,765,527` B, MD5 `c93201502c88b9280a7f5d8c223ca5e6`
* `input/LUM_data/LUMClasses.xlsx`: `15,226` B, MD5 `03a7ba080c40646dbc6c047a9674778c`
* `input/EPIC/Grassland/YLDF/` (14 files): combined MD5 digest `22d2779d37bd8cc6cf09b13f9c872a34`
* `input/EPIC/Grassland/Externalities/` (53 files): combined MD5 digest `702df7dd1d25a0978cf7b885de7bc693`
* `input/EPIC/Grassland/Auxiliary/GRS_LUM_AreaHa_BySimUID.txt`: `13,366,660` B, MD5 `6129ebbf15d9f90679d58125dbea1228`
* `input/targets/pasture/faostat_raw/` (chmod `444`):
  * `Production_Crops_Livestock_E_Europe.zip` (`3,882,548` B, MD5 `6703648d51ed53dc7b9f66f5c278a8bd`)
  * `Emissions_livestock_E_Europe.zip` (`6,241,135` B, MD5 `0f998d4e10bf22e49402032e04aea3ac`)
  * `Environment_LivestockManure_E_Europe.zip` (`4,016,211` B, MD5 `e4551fbba45d5e226235c2defdf9a3c8`)
  * `Environment_LivestockPatterns_E_Europe.zip` (`280,059` B, MD5 `639890cffb08eb6c6150ad1a220c65ee`)

---

## 3. Data & Control-Flow DAG (`P00`–`P16`)

```text
  P00_check_env.R           Verify 22 R packages, GDAL drivers (GPKG/COG/arrow), multi-root LUM/input paths,
         │                  and external/cascade-core (cascadecore::fienberg)
         ▼
  P02_prepare_pasture_inputs.R   Prepare missing/forced artifacts via standalone prep_*.R -> canonical .parquet (+ .json)
         │
         ▼
  P03_load_shared_pasture.R      Magic-byte hydration checks (PAR1/TIFF/RDS), load Parquet inputs, filter CY,
         │                       assert_contract key = CELLCODE (4,927,404 cells) & band catalogue
         ▼
  Per country x year loop [main_pasture.R -> AT, ES, NL (2018)]:
    ├── P04_initialize_country.R         Resolve ibiom_LUM_europe_100m_2018.tif (BigTIFF), NUTS0 cells, border NUTS2
    ├── P05_prepare_pasture_startmap.R   Crop 100 m COG (LUM 15..25) -> (CELLCODE, LUM.class); log G12/C1-C2/leftover
    ├── P07_load_EPIC_grass.R            Left join EPIC_grass_params by (SimUID, LUM.class); compute forage_dm_t
    ├── P09_livestock_disaggregation.R   gamma_c = B_c/LSU_c; 2D IPF via cascadecore::fienberg(); record KL prior D_r
    ├── P10_milk_meat_production.R       Reconcile carcass meat & milk (NUTS2 agr_r_milkpr index) to FAOSTAT QCL
    ├── P11_emissions_accounting.R       Species GLE/EMN emissions per head; land CO2_SOC & synthetic N2O (1:1 join)
    └── P12_country_outputs.R            24-band FLT4S COG (NA=-9999) + raster-to-table check + GPKG + Parquet + .json
         │
         ▼
  P13_summarise.R           Resolve explicit country_grid paths, assert cross-table sums, save _pasture.rds & 6 Parquets
         │
         ├──▶ P15_aggregate_SimU_LU.R   Aggregate lum_all -> simu_lum & simu_total (.rds, .parquet, .json)
         ├──▶ P13b_performance_checks.R 5 non-self-contained external & sub-national benchmarks + baselines (.csv/.parquet/.json)
         ├──▶ P14_plot_results.R        Non-self-contained benchmark panel & gamma_c vs EW-MFA plots
         ├──▶ run_manifest.rds / .json  Write provenance, lum_files, config, engine_cascade_core, input MD5s
         └──▶ P16_run_report.R          Build report_objects.rds, CSVs, 5 PNGs, Markdown & self-contained HTML
```

---

## 4. Fallbacks & Exclusions Logged (`fallbacks_log.csv`)

All 6 logged events from `pasture_v1` (using `ibiom_LUM_europe_100m_2018.tif`):

| Stage | Country | Year | Kind | What Happened | Affected Share |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `P03_load_shared` | `CY` | `2018` | `excluded_country` | `CY` skipped (`0` pixels in 1 km grid mapping and absent from FAOSTAT Europe bulk files) | `100.00%` |
| `P04_initialize` | `AT` | `2018` | `border_nuts2_mismatch` | Border 1 km cells carried imputed neighboring codes (`SK01,DE21`); priors fell back to national shares | `0.0024%` (`2.38e-5`) |
| `P07_load_EPIC` | `AT` | `2018` | `epic_missing_simuid` | `134` of `49,300` rows (`1,035.0 ha`) missing SimUID in EPIC filled with country `LUM.class` weighted mean | `0.107%` (`1.07e-3`) |
| `P09_disaggregation` | `AT` | `2018` | `eurostat_nuts2_prior_partial` | Border/unmapped NUTS2 cells fell back to national FAOSTAT species shares (`100.00%` matched; remainder national) | `0.0015%` (`1.48e-5`) |
| `P07_load_EPIC` | `ES` | `2018` | `epic_missing_simuid` | `544` of `237,934` rows (`4,517.0 ha`) missing SimUID in EPIC filled with country `LUM.class` weighted mean | `0.081%` (`8.10e-4`) |
| `P07_load_EPIC` | `NL` | `2018` | `epic_missing_simuid` | `49` of `26,708` rows (`304.0 ha`) missing SimUID in EPIC filled with country `LUM.class` weighted mean | `0.042%` (`4.16e-4`) |

---

## 5. Quantitative Verification & Conservation Ledger (`pasture_v1`)

Across all `65` ledger checks in `output/pasture_v1/report/conservation_ledger.csv` (including double-precision COG raster-vs-table verification across all 20 extensive bands), the maximum relative deviation between allocated totals and stage/national targets is **`6.608025e-14`** (on `ES` `2018` `heads_non_dairy_cattle`), and maximum `FLT4S` COG vs. table deviation is **`1.94e-09`** (`NL`, `4.87e-10` `AT`, `5.91e-10` `ES`).

### 5.1 Country Summary (`country_summary.csv` — `ibiom_LUM_europe_100m_2018.tif`)

| Country | Pasture Area (`ha`) | Forage (`t DM`) | Mean `YLDF` (`t/ha`) | `LSU_total` | `gamma_c` (`t DM/LSU/yr`) | `MF1222/LSU` (`t DM/LSU/yr`) | `CO2_SOC_t` (`t CO2`) | `N2O_synth_fert_total_t` (`t N2O`) | `GHG_total_CO2e_t` (`t CO2e`) | `cascadecore::fienberg` Iters | Excluded Grass Aux (`G12 / C1+C2 / Leftover` ha) |
| :--- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | :--- |
| `AT` | `969,673` | `2,898,335.9` | `2.989` | `1,771,317.0` | `1.636` | `0.594` | `-845,517.2` | `237.26` | `4,752,408.0` | `500` | `274,778 / 16,054 / 146,015` |
| `ES` | `5,577,821` | `9,756,998.2` | `1.749` | `7,721,263.0` | `1.264` | `3.067` | `-4,089,534.6` | `435.27` | `18,114,526.5` | `26` | `1,314,778 / 99,936 / 365,218` |
| `NL` | `730,948` | `4,875,803.4` | `6.671` | `3,447,100.0` | `1.414` | `0.744` | `-841,080.0` | `168.20` | `11,219,750.1` | `15` | `23,958 / 6,755 / 228,865` |

### 5.2 Non-Self-Contained Performance Benchmarks (`P13b_performance_checks.R`)

* **Check 1 (NUTS2 Species Allocation vs. Eurostat FSS `ef_lsk_*` & Spatial Baselines):** $R^2$ (`IPF` vs. `Forage baseline` / `Area baseline`): `goats` `0.850` vs `0.085` / `0.331`; `sheep` `0.890` vs `0.529` / `0.834`; `dairy_cattle` `0.574` vs `0.533` / `0.455`; `non_dairy_cattle` `0.630` vs `0.649` / `0.674` (share $R^2 = 0.687$ vs `0.594`).
* **Check 2 (Pure Biophysical Carrying Capacity vs. Eurostat FSS LSU):** `AT` $R^2 = 0.928$ (Spearman $0.950$, `10.0 pp` disagr vs `16.6 pp` area baseline), `ES` $R^2 = 0.684$ ($0.882$), `NL` $R^2 = 0.403$ ($0.699$); KL prior divergence $D_r = 0.001-0.010$; soft compositional agreement `0.947–0.979`.
* **Check 3 (NUTS2 Cow Milk vs. `agr_r_milkpr`):** `AT` $R^2 = 0.903$ (RMSE `121.8 kt`), `ES` $R^2 = 0.520$ (vs `0.114` forage baseline; RMSE `449.1 kt`), `NL` $R^2 = 0.532$ (RMSE `792.9 kt`).
* **Check 4 (`SimUID` Agreement vs. EPIC `GRS_LUM_AreaHa_BySimUID` & `REF`):** Area $R^2 = 0.733$ (`AT`), `0.794` (`ES`), `0.716` (`NL`); Forage $R^2 = 0.790$ (`AT`), `0.738` (`ES`), `0.723` (`NL`).
* **Check 5 (Independent National Benchmarks — EW-MFA `MF1222` & UNFCCC NIR):** Direct-grazing $\gamma_{c,\text{direct}}/\text{MF1222} = 1.023$ (`AT`, `0.61 vs 0.59 t DM/LSU/yr`) and `1.169` (`NL`, `0.87 vs 0.74`), `0.334` (`ES`); Enteric $\text{CH}_4$ Tier 1 vs UNFCCC NIR rel. diff = `-4.5%` (`AT`), `+1.5%` (`ES`), `+1.5%` (`NL`).

### 5.3 Land-Level Emission Integrity

* `P11` explicitly verified exact equality (`rel_diff` $\le 1.35 \times 10^{-14}$) between `sum(cell_summary$CO2_SOC_t)` and `sum(temp.pasture$CO2_SOC_t)`, and between `sum(cell_summary$N2O_synth_fert_total_t)` and `sum(temp.pasture$N2O_synth_fert_total_t)` across all three countries (`zero species multiplication`).
* Diagnostic raw `NFERT` $\text{N}_2\text{O}$ (`N2O_epic_raw_nfert_diag_t`: `AT 1,232.2 t`, `ES 6,592.3 t`, `NL 1,341.7 t`) is stored alongside decomposed synthetic N2O (`AT 237.3 t`, `ES 435.3 t`, `NL 168.2 t`) to document removal of organic manure N (`FCO/12`) and `LUM 23..25` exclusion.

---

## 6. Verified Deliverable Artifacts (`output/pasture_v1/`)

* **Legend & Config Sidecar:** `pasture_band_catalogue.csv` (`2.9K`)
* **Country RDS (`P12`):** `AT_2018_pasture_v1.rds` (`35M`), `ES_2018_pasture_v1.rds` (`176M`), `NL_2018_pasture_v1.rds` (`16M`)
* **Spatial Exports (`country_res/`, `EPSG:3035`, each with `<file>.json` sidecar):**
  * 24-band `FLT4S` (`NAflag = -9999`) COG GeoTIFFs: `AT` (`5.6M`), `ES` (`28M`), `NL` (`2.1M`)
  * 1 km centroid GeoPackages: `AT` (`13M`), `ES` (`60M`), `NL` (`7.6M`)
  * Tabular Parquet via `arrow`: `AT` (`6.9M`), `ES` (`33M`), `NL` (`3.3M`)
* **Aggregated & SimU Bundles (Canonical Parquet + `.rds` + `.json` sidecars):**
  * `aggregated/pasture_v1_pasture.rds` (`227M`), `cell_all.parquet` (`43M`), `lum_all.parquet` (`61M`), `species_alloc.parquet` (`200M`), `species_summary.parquet` (`13K`), `country_summary.parquet` (`14K`), `nuts2_summary.parquet` (`10K`)
  * `simu_res/pasture_v1_SimU_res.rds` (`14M`), `simu_lum.parquet` (`15M`), `simu_total.parquet` (`4.4M`)
* **Performance Benchmarks, Reports & Plots:**
  * `report/`: `performance_summary.rds` (`891K`), 6 `performance_*.{csv,parquet,parquet.json}` files, `report_objects.rds` (`898K`), CSV audit tables (`country_summary.csv`, `species_targets_fulfilment.csv`, `conservation_ledger.csv`, `fallbacks_log.csv`)
  * `report/pasture_v1_run_report.md` (`8.6K`) and self-contained `report/pasture_v1_run_report.html` (`4.0M`)
  * `report/fig/`: `00_eu_pasture_overview.png` (`1.3M`), `01_eu_production_and_soil.png` (`882K`), `02_independent_performance_checks.png` (`765K`), `03_grazing_feed_coefficient_comparison.png` (`46K`), `04_ghg_breakdown_and_sources.png` (`77K`)
  * `plot/`: `pasture_independent_performance.png` (`765K`), `grazing_feed_coef_and_mfa.png` (`46K`)
