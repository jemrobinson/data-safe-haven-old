import json
import os

def get_dsg_config(dsg_id):
    # Load configuration from file
    filepath = os.path.join("..", "dsg_configs", "full", "dsg_{}_full_config.json".format(dsg_id))
    if not os.path.isfile(filepath):
        raise FileNotFoundError("Could not open {}".format(filepath))
    config = None
    with open(filepath, "r") as f_config:
        config = json.load(f_config)
    if not config:
        raise FileNotFoundError("Could not read {}".format(filepath))
    return config


    #     param(
    #     [string]$dsgId
    # )
    # # Read DSG config from file
    # $configRootDir = Join-Path $PSScriptRoot ".." "dsg_configs" "full" -Resolve;
    # $configFilename =  "dsg_" + $dsgId + "_full_config.json";
    # $configPath = Join-Path $configRootDir $configFilename -Resolve;
    # $config = Get-Content -Path $configPath -Raw | ConvertFrom-Json;
    # return $config
