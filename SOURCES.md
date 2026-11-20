# Data Source Cards (`SOURCES.md`)

Provenance registry for all raw exogenous datasets used by the Pasture & Ruminant Livestock module (`pasture_livestock` branch). All raw files reside read-only under `input/`.

---

## 1. LAMASUS / iBIOM 100 m Land Use and Management (LUM) Rasters

| Field | Value |
| :--- | :--- |
| **Name / Provider** | LAMASUS Land Use and Management (LUM) 100 m Geodatabase — `ibiom_LUM_europe_100m_<year>.tif` v1.0.0 (`DOI: 10.5281/zenodo.21787459`, IIASA / LAMASUS Horizon Europe) |
| **Access / Origin** | **Primary (IIASA Accelerator `ibiom` storage):** `iBIOM_Explorer/Land_use_and_management/<year>/ibiom_LUM_europe_100m_<year>.tif` (`/mnt/wdrv/...` in WKUBE; `~/accelerator/mnt/ibiom/...` via `accli mount start ibiom`).<br>**Local fallback:** `input/LUM_data/LUM_<year>.tif` (from WP5 staging). |
| **Coverage** | Europe (`[-55.5, 24.5, 61.0, 72.1]`, EPSG:3035 extent `[918900, 916700, 6552100, 5440900]`); discrete snapshots `2000`, `2010`, `2018`; 100 m pixel (`1 ha = 0.01 km^2`) |
| **CRS & Format** | ETRS89-extended / LAEA Europe (`EPSG:3035`); BigTIFF Cloud-Optimized GeoTIFF (`II+`, `0x49 0x49 0x2b 0x00`) |
| **Definitions** | Categorical land-use/management classes (`LUM_fit_with_energy_levels_and_new_FM_<year>.qml`): pasture/grassland `15..25` (`G1..G11`), unmanaged grassland `26` (`G12`), arable energy levels `2001..2005` (`A1..A5`), permanent crops `3001..3005` (`P1..P5`), heterogeneous grassland `4012..4013` (`C1/C2`), leftover grassland `40000`. |
| **Files (Observed)** | **Hosted COGs (`iBIOM_Explorer/Land_use_and_management/`):** `ibiom_LUM_europe_100m_2000.tif` (`189M`), `ibiom_LUM_europe_100m_2010.tif` (`192M`), `ibiom_LUM_europe_100m_2018.tif` (`192M`), accompanied by `README_ibiom_LUM_europe_100m_<year>.yaml` and `.qml`.<br>**Local fallback (`input/LUM_data/`):** `LUM_2000.tif` (`99,541,502` B, MD5 `743b5da53f9c4b5896300f7bb733591c`), `LUM_2010.tif` (`101,499,068` B, MD5 `d3e4f4aea649e3f3649fb004efef6931`), `LUM_2018.tif` (`101,765,527` B, MD5 `c93201502c88b9280a7f5d8c223ca5e6`), `LUMClasses.xlsx` (`15,226` B, MD5 `03a7ba080c40646dbc6c047a9674778c`) |

---

## 2. EPIC-IIASA Grassland Forage Yield, Soil Externalities & Reference Tables

| Field | Value |
| :--- | :--- |
| **Name / Provider** | EPIC-IIASA Grassland Simulations for LAMASUS (IIASA, Juraj Balkovic et al.) |
| **Access / Origin** | Copied from WP5 staging (`WP 5/EPIC-IIASA/Grassland/`) into `input/EPIC/Grassland/` (processed standalone via [`codes/support/prep_EPIC_grass.R`](codes/support/prep_EPIC_grass.R) into canonical Apache Parquet + JSON sidecars) |
| **Coverage** | `352,845` EU Simulation Units (`SimUID`); `12` grassland LUM classes (`LUM15`..`LUM26`, `4,234,140` rows) + `REF` scenario + `GRS_LUM_AreaHa_BySimUID.txt` (`X15`..`X26`, `GRS.Area`) |
| **Definitions** | `YLDF` (`t DM/ha/yr` forage yield), `OCPD.init` (`t C/ha` initial topsoil SOC), `dOCPD` (`t C/ha/yr` 20-year mean annual SOC change), `NFERT` (`kg N/ha/yr` total mineral + organic fertilizer N input), `FCO` (`kg C/ha/yr` organic fertilizer C input), `RSDC` (`kg C/ha/yr` grass residue C input), `Area.ha` (`epic_area_ha`), plus `REF` weighted reference yields/externalities and `GRS_LUM_AreaHa_BySimUID.txt` per-`SimUID` areas (`EPIC_grass_simu_ref.parquet`). **Known limitation:** `NFERT` and `FCO` are invariant across `LUM15..26` and combine organic + mineral N (`Externalities/ReadMe.txt`). |
| **Files & MD5** | `YLDF/`: 14 files (`LUM15`..`LUM26`, `REF`, `ReadMe.txt`), combined MD5 digest of sorted MD5s `22d2779d37bd8cc6cf09b13f9c872a34`<br>`Externalities/`: 53 files (`dOCPD`, `FCO`, `NFERT`, `RSDC` across `LUM15`..`LUM26`, `REF`, `ReadMe.txt`), combined MD5 digest `702df7dd1d25a0978cf7b885de7bc693`<br>`Auxiliary/GRS_LUM_AreaHa_BySimUID.txt` (`13,366,660` B, MD5 `6129ebbf15d9f90679d58125dbea1228`)<br>**Processed Parquets:** `input/EPIC/EPIC_grass_params.parquet` (`29M`, MD5 `237db39dcb9a3be813cdb64da6c77710`), `input/EPIC/EPIC_grass_simu_ref.parquet` (`18M`, MD5 `58c21a9a76fdb4df8e0a9747e86258f2`) |

---

## 3. 1 km EEA Reference Grid to SimUID & NUTS Mapping

| Field | Value |
| :--- | :--- |
| **Name / Provider** | LAMASUS 1 km Grid to SimUID & NUTS 2016 Imputed Mapping (IIASA WP5) |
| **Access / Origin** | Copied from WP5 staging (`WP 5/D5.4 - Joint maps/aux_files/`) into `input/mappings/` |
| **Coverage** | `4,927,404` unique 1 km cells (`EPSG:3035` cell centres `x, y`); covers 27 of 28 EU-27 + UK countries (**Cyprus `CY` has 0 rows**; Malta `MT` has `315` rows). |
| **Reference System** | `EPSG:3035`, `NUTS 2016` administrative codes (`NUTS0`, `NUTS1`, `NUTS2`, `NUTS3`) |
| **Files & MD5** | `one_km_to_lower_resolution_mapping_NUTS_2016_imputed.rds` (`22,845,105` B, MD5 `b313ede6d8c2c6a21a0f1b9f52f80aae`)<br>`LAMA_NUTS_EPIC_SimUID.rds` (`3,205,076` B, MD5 `064cae3cf2e30300418271b738818eff`)<br>`NUTS2021-NUTS2024.xlsx` (`537,899` B, MD5 `7f1e135b556d5b26edaa03d01ee686a6`) |

---

## 4. FAOSTAT Bulk Europe Datasets (National Livestock, Production, Manure & Emissions)

| Field | Value |
| :--- | :--- |
| **Name / Provider** | FAOSTAT (Food and Agriculture Organization of the United Nations) — Domains `QCL`, `GLE`, `EMN`, `EK` |
| **Access / Version** | Bulk Europe downloads (`https://bulks-faostat.fao.org/production/*.zip`), archived read-only in `input/targets/pasture/faostat_raw/` (accessed 2026-11-20) |
| **Licence** | CC BY-NC-SA 3.0 IGO (FAOSTAT Open Data Terms of Use) |
| **Coverage** | Europe (`1961`–`2024`); covers all EU-27 + UK countries present in the 1 km grid |
| **Definitions** | `QCL` (`Production_Crops_Livestock_E_Europe.zip`): stocks (`An`), milk animals (`An`), raw milk & carcass meat (`t`).<br>`GLE` (`Emissions_livestock_E_Europe.zip`): species-level (`Cattle, dairy`, `Cattle, non-dairy`, `Sheep`, `Goats`) stocks (`An`) and enteric/manure/pasture/applied-soils `CH4` and `N2O` (`kt`) for both `FAO TIER 1` and `UNFCCC`.<br>`EMN` (`Environment_LivestockManure_E_Europe.zip`): species-level N excretion, pasture PRP N, MMS treated N, and soil-applied N (`kg N`).<br>`EK` (`Environment_LivestockPatterns_E_Europe.zip`): official FAOSTAT Livestock Units (`Stocks` in `LSU` for `Cattle`, `Sheep`, `Goats`). |
| **Files & MD5** | `Production_Crops_Livestock_E_Europe.zip` (`3,882,548` B, MD5 `6703648d51ed53dc7b9f66f5c278a8bd`)<br>`Emissions_livestock_E_Europe.zip` (`6,241,135` B, MD5 `0f998d4e10bf22e49402032e04aea3ac`)<br>`Environment_LivestockManure_E_Europe.zip` (`4,016,211` B, MD5 `e4551fbba45d5e226235c2defdf9a3c8`)<br>`Environment_LivestockPatterns_E_Europe.zip` (`280,059` B, MD5 `639890cffb08eb6c6150ad1a220c65ee`) |

---

## 5. Eurostat Spatial Priors & EW-MFA Benchmark (via `eurostat` API)

| Field | Value |
| :--- | :--- |
| **Name / Provider** | Eurostat (European Commission) — Farm Structure Survey (`ef_lsk_bovine`, `ef_lsk_sheep`, `ef_lsk_goats`), Regional Cow Milk (`agr_r_milkpr`), Economy-Wide Material Flow Accounts (`env_ac_mfa`) |
| **Access / Version** | Eurostat Dissemination API (`eurostat` R package `4.0.0`), cached to `input/targets/pasture/eurostat_priors_nuts2.rds` |
| **Licence** | CC BY 4.0 (European Commission Reuse Policy) |
| **Coverage & Notes** | NUTS2 livestock head counts (`HD`) across FSS waves (`2005, 2007, 2010, 2013, 2016, 2020`); `agr_r_milkpr` cow milk (`1000 t`, annual); `env_ac_mfa` (`MF1221`, `MF1222`, `1000 t` at 15% moisture, NUTS0, 1990–2025). FSS waves use NUTS2016/2021 codes and are explicitly harmonized to the grid's NUTS2016 codes; any missing/suppressed NUTS2 cells preserve Eurostat flags and roll up transparently to national shares. |

