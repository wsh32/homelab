terraform {
  backend "s3" {
    bucket = "terraform-state"
    key    = "nuc/terraform.tfstate"

    # MinIO on NUC
    endpoint                    = "http://minio.home:9000"
    region                      = "us-east-1" # required by S3 backend, value ignored by MinIO
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true

    # Credentials via env: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  }
}
