provider "aws" {
  region = var.aws_region

  # Tags en todos los recursos: permite filtrar costos y recursos por ambiente.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
