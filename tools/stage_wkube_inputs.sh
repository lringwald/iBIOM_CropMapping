#!/usr/bin/env bash
# Stage both prepared canonical inputs (.parquet / .rds + .json sidecars) AND
# raw EPIC Grassland + FAOSTAT ZIP sources onto the mounted ibiom Accelerator drive
# (/mnt/wdrv/Data/preprocessed_data/iBIOM_CropMapping_input).
set -euo pipefail

MOUNT_ROOT="${IBIOM_MOUNT:-$HOME/accelerator/mnt/ibiom}"
DEST_ROOT="$MOUNT_ROOT/Data/preprocessed_data/iBIOM_CropMapping_input"

if [ ! -d "$MOUNT_ROOT/iBIOM_Explorer" ]; then
  echo "ERROR: ibiom mount not active at $MOUNT_ROOT." >&2
  echo "Run: accli mount start ibiom" >&2
  exit 1
fi

mkdir -p \
  "$DEST_ROOT/EPIC/Grassland/YLDF" \
  "$DEST_ROOT/EPIC/Grassland/Externalities" \
  "$DEST_ROOT/EPIC/Grassland/Auxiliary" \
  "$DEST_ROOT/mappings" \
  "$DEST_ROOT/targets/pasture/faostat_raw"

copy_if_present() {
  local src="$1" dst="$2"
  if [ ! -f "$src" ]; then
    echo "WARNING: missing local file $src (skipping)" >&2
    return 0
  fi
  echo ">>> Staging $(basename "$src") -> $dst"
  cp -f "$src" "$dst"
}

copy_dir_files() {
  local src_dir="$1" dst_dir="$2"
  [ -d "$src_dir" ] || return 0
  mkdir -p "$dst_dir"
  for f in "$src_dir"/*; do
    [ -f "$f" ] || continue
    cp -f "$f" "$dst_dir/$(basename "$f")"
  done
}

# Prepared canonical Parquet & RDS tables (+ JSON sidecars)
for f in \
  input/EPIC/EPIC_grass_params.rds \
  input/EPIC/EPIC_grass_params.parquet \
  input/EPIC/EPIC_grass_params.parquet.json \
  input/EPIC/EPIC_grass_simu_ref.rds \
  input/EPIC/EPIC_grass_simu_ref.parquet \
  input/EPIC/EPIC_grass_simu_ref.parquet.json
do
  copy_if_present "$f" "$DEST_ROOT/EPIC/$(basename "$f")"
done

copy_if_present "input/mappings/one_km_to_lower_resolution_mapping_NUTS_2016_imputed.rds" \
  "$DEST_ROOT/mappings/one_km_to_lower_resolution_mapping_NUTS_2016_imputed.rds"

for f in \
  input/targets/pasture/faostat_national_accounts.rds \
  input/targets/pasture/faostat_national_accounts.parquet \
  input/targets/pasture/faostat_national_accounts.parquet.json \
  input/targets/pasture/eurostat_priors_nuts2.rds \
  input/targets/pasture/eurostat_priors_nuts2_livestock.parquet \
  input/targets/pasture/eurostat_priors_nuts2_livestock.parquet.json \
  input/targets/pasture/eurostat_priors_nuts2_milk.parquet \
  input/targets/pasture/eurostat_priors_nuts2_milk.parquet.json \
  input/targets/pasture/eurostat_priors_nat_mfa.parquet \
  input/targets/pasture/eurostat_priors_nat_mfa.parquet.json
do
  copy_if_present "$f" "$DEST_ROOT/targets/pasture/$(basename "$f")"
done

copy_if_present "output/country_grid.rds" "$DEST_ROOT/country_grid.rds"

# Raw EPIC Grassland parameter files & raw FAOSTAT archives
echo ">>> Staging raw EPIC Grassland parameter files (YLDF, Externalities, Auxiliary)..."
copy_if_present "input/EPIC/Grassland/LUMClasses.xlsx" "$DEST_ROOT/EPIC/Grassland/LUMClasses.xlsx"
copy_dir_files "input/EPIC/Grassland/YLDF" "$DEST_ROOT/EPIC/Grassland/YLDF"
copy_dir_files "input/EPIC/Grassland/Externalities" "$DEST_ROOT/EPIC/Grassland/Externalities"
copy_dir_files "input/EPIC/Grassland/Auxiliary" "$DEST_ROOT/EPIC/Grassland/Auxiliary"
copy_dir_files "input/targets/pasture/faostat_raw" "$DEST_ROOT/targets/pasture/faostat_raw"

echo ">>> Staging complete under $DEST_ROOT"
ls -lh "$DEST_ROOT/EPIC" "$DEST_ROOT/mappings" "$DEST_ROOT/targets/pasture"
