terraform {
  backend "s3" {
    bucket = "terraform-state"
    key    = "anton/terraform.tfstate"

    endpoint                    = "http://minio.home:9000"
    region                      = "us-east-1"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
  }
}
