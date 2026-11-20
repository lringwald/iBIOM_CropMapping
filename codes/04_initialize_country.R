##### CODE 04: initialisation per country and year

#### Author: Michael Wögerer
#### Date: Dec/2024


#### current country and year


  curr.year <- as.character(country_grid[JOB,"years"])
  country <- as.character(country_grid[JOB,"countries"])
  lama.reg <- as.character(country_grid[JOB,"lama.regs"])


##### identify curr prior
prior <- list.files(prior.path, full.names = TRUE)
prior <- prior[grepl(curr.year,prior)]

#### identify curr LUM map and LUMenergy map (prefers hosted iBIOM_Explorer 100m COG if available)
lum_resolved <- if (exists("resolve_lum_raster", mode = "function")) {
  resolve_lum_raster(curr.year, lum_dir = LUM.path, input_dir = INPUT_DIR, must_exist = FALSE)
} else ""

if (nzchar(lum_resolved) && file.exists(lum_resolved)) {
  LUM <- lum_resolved
} else {
  LUM <- list.files(LUM.path, full.names = TRUE)
  LUM <- LUM[grepl(curr.year, LUM)]
  LUM <- LUM[!grepl("\\.(ovr|qml|aux|xml|yaml)$", LUM)]
}

if (grepl("^ibiom_LUM_europe_100m_", basename(LUM[1]))) {
  LUMenergy <- LUM[1]
} else {
  LUMenergy <- list.files(LUM.energy.path, full.names = TRUE)
  LUMenergy <- LUMenergy[grepl(curr.year, LUMenergy)]
  LUMenergy <- LUMenergy[!grepl("\\.(ovr|qml|aux|xml|yaml)$", LUMenergy)]
}

#### identify curr EEA map
EEA.grid <- list.files(EEA.path, full.names = TRUE)
EEA.grid <- EEA.grid[grepl(country,EEA.grid)]
EEA.grid <- list.files(EEA.grid, full.names = TRUE)
EEA.grid <- EEA.grid[grepl(".shp",EEA.grid)]

# #### irrigation map
# irrig.path <- list.files(file.path(INPUT_DIR, "irrigation/"), full.names = T)
# irrig.path <- irrig.path[!grepl(".ovr",irrig.path)]
# irrig.path <- irrig.path[!grepl(".qml",irrig.path)]
# irrig.path <- irrig.path[!grepl(".aux",irrig.path)]

#### load mapping for country
EEA_NUTS <- read.csv(file.path(mapping.path,"EEAref_LAMAnuts_mapping_oct17.csv"))
length.curr.nuts <- nchar(lama.reg)
curr.EEA_NUTS <- EEA_NUTS %>% filter(substr(NUTS_ID,1,length.curr.nuts)==lama.reg)

### mapping of the priors
crop_mapping <- read.csv(file.path(mapping.path,"CROP_mapping.csv"))
colnames(crop_mapping)[1] <- "CAPRI"
setDT(crop_mapping)

##### irrigation mapping
aqua_to_globiom <- tribble(
  ~Item,                ~GLOBIOM,
  "Wheat",              "Whea",
  "Barley",             "Barl",
  "Potatoes",           "Pota",
  "Soybeans",           "Soya",
  "Sugar beet",         "Sgbt",
  "Sunflower",          "Sunf",
  "Maize",              "Corn",
  "Rice",               "Rice",
  "Other cereals",      "Srgh",
  "Other cereals",      "Mill",
  "Other cereals",      "WRye",
  "Leguminous crops",   "BeaD",
  "Leguminous crops",   "ChkP",
  "Other crops",        "Cass",
  "Other crops",        "SwPo",
  "Other crops",        "SugC",
  "Cotton",             "Cott",
  "Other crops",        "Rape",
  "Other crops",        "Gnut"
)
