# Remote state for the Muskan & Sourav stack.
# See the repo-root backend.tf for why each skip_* flag is needed, and
# README "Remote state bootstrap".
#
#   terraform init \
#     -backend-config="bucket=imigrate-tfstate" \
#     -backend-config="key=weddings/muskan-sourav/terraform.tfstate"
#
# The key is passed on the command line rather than hardcoded so that the
# `make new-wedding` copy of this directory cannot accidentally inherit
# another wedding's state path. CI derives it from the directory name.

terraform {
  backend "s3" {
    endpoints = {
      s3 = "https://sgp1.digitaloceanspaces.com"
    }

    region  = "us-east-1"
    encrypt = true

    skip_credentials_validation = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    skip_s3_checksum            = true

    use_path_style = false
  }
}
