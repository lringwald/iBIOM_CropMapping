"""IIASA Accelerator WKUBE routine definitions for project `ibiom`.

Usage (always ask user before dispatching):
    accli login
    bash tools/stage_wkube_inputs.sh          # ensure non-LUM .rds inputs exist on /mnt/wdrv
    accli dispatch ibiom trial   -f wkube.py  # fast AT/NL/ES 2018 end-to-end verification
    accli dispatch ibiom pasture_2018 -f wkube.py
    accli logs ibiom <job_id> --follow

By default (when IBIOM_REPO_URL / IBIOM_REPO_REF are unset), `WKubeTask` uses accli's CAS
`job_folder` upload directly from this checkout (excluding heavy local input/output/.git
directories). Set IBIOM_REPO_URL and IBIOM_REPO_REF to build directly from a pushed
GitHub tag/branch instead.
"""
import os
import subprocess
from accli import WKubeTask

HERE = os.path.dirname(os.path.abspath(__file__))
GB = 1024 ** 3

PROJECT_WORK_ROOT = "/mnt/wdrv/iBIOM_pasture_livestock"
LUM_HOSTED_DIR = "/mnt/wdrv/iBIOM_Explorer/Land_use_and_management"
SHARED_PREPROC_DIR = "/mnt/wdrv/Data/preprocessed_data/iBIOM_CropMapping_input"

REPO_URL = os.environ.get("IBIOM_REPO_URL", "").strip()
REPO_REF = os.environ.get("IBIOM_REPO_REF", "").strip()
if REPO_URL and not REPO_REF:
    REPO_REF = subprocess.run(
        ["git", "-C", HERE, "rev-parse", "--abbrev-ref", "HEAD"],
        check=True, capture_output=True, text=True
    ).stdout.strip()

GIT_SECRETS = {
    "ACC_WKUBE_GIT_USER": os.environ.get("ACC_WKUBE_GIT_USER_SECRET", "GIT_USER"),
    "ACC_WKUBE_GIT_PASSWORD": os.environ.get("ACC_WKUBE_GIT_PASSWORD_SECRET", "GIT_TOKEN"),
}

CAS_EXCLUDE = "input/*,input/**,output/*,output/**,.git/*,.git/**,.rules-hub/*,.rules-hub/**,*.RData,*.Rhistory,.DS_Store"


def routine(name, task, tag, years="2018", countries="all", result_tag="pasture_v1",
            cores=4, ram_gb=16, disk_local_gb=20, disk_work_gb=40, hours=6,
            extra_conf=None):
    """Build a WKubeTask with unique per-tag WORK_DIR so /mnt/wdrv GIDs never collide."""
    conf = {
        "TASK": task,
        "YEARS": str(years),
        "COUNTRIES": str(countries),
        "RESULT_TAG": str(result_tag),
        "LUM_DIR": LUM_HOSTED_DIR,
        "WORK_DIR": f"{PROJECT_WORK_ROOT}/{tag}",
        "SHARED_INPUT_DIR": SHARED_PREPROC_DIR,
        "OUTPUT_DIR": "output",
        "LIVESTOCK_SOURCE": "faostat",
        "EMISSION_SOURCE": "FAO TIER 1",
        "USE_EUROSTAT_PRIORS": "1",
        "GWP_VERSION": "AR6",
        "EXPORT_SPATIAL": "1",
        "SKIP_EXISTING": "0",
        "FORCE_PREP": "",
        "NCORES": str(cores),
        "TRIAL": "1" if task == "trial" else "0",
    }
    if extra_conf:
        conf.update({k: str(v) for k, v in extra_conf.items()})

    source_kwargs = (
        {"repo_url": REPO_URL, "repo_branch": REPO_REF, "job_secrets": GIT_SECRETS}
        if REPO_URL else
        {"job_folder": HERE, "exclude": CAS_EXCLUDE}
    )

    return WKubeTask(
        name=f"ibiom-pasture: {name}",
        docker_filename="Dockerfile",
        command="/app/entrypoint.sh",
        required_cores=cores,
        required_ram=ram_gb * GB,
        required_storage_local=disk_local_gb * GB,
        required_storage_workflow=disk_work_gb * GB,
        timeout=hours * 3600,
        conf=conf,
        **source_kwargs,
    )


check = routine(
    "environment & mounted LUM check",
    task="check", tag="check", years="2018", countries="AT,NL,ES",
    cores=2, ram_gb=8, disk_local_gb=10, disk_work_gb=10, hours=1,
)

trial = routine(
    "trial (AT, NL, ES 2018)",
    task="trial", tag="trial-2018", years="2018", countries="AT,NL,ES",
    result_tag="pasture_v1", cores=4, ram_gb=16, disk_local_gb=20, disk_work_gb=20, hours=2,
)

pasture_2018 = routine(
    "EU-27 + UK pasture & livestock (2018)",
    task="pasture", tag="pasture-2018", years="2018", countries="all",
    result_tag="pasture_2018", cores=8, ram_gb=32, disk_local_gb=30, disk_work_gb=50, hours=12,
)

pasture_all_years = routine(
    "EU-27 + UK pasture & livestock (2000, 2010, 2018)",
    task="pasture", tag="pasture-2000-2018", years="2000,2010,2018", countries="all",
    result_tag="pasture_multi_year", cores=8, ram_gb=32, disk_local_gb=40, disk_work_gb=80, hours=24,
)

cropland = routine(
    "EU cropland downscaling (2018)",
    task="cropland", tag="cropland-2018", years="2018", countries="all",
    result_tag="res_v1", cores=8, ram_gb=32, disk_local_gb=30, disk_work_gb=50, hours=24,
)

all_tasks = routine(
    "pasture + cropland full pipeline (2018)",
    task="all", tag="all-2018", years="2018", countries="all",
    result_tag="ibiom_2018", cores=8, ram_gb=32, disk_local_gb=40, disk_work_gb=80, hours=36,
)
all = all_tasks  # noqa: A001
