# -----------------------------------------------------------------------------
# Remote state backend
# -----------------------------------------------------------------------------
# For a real project, use S3 + DynamoDB locking:
#
# terraform {
#   backend "s3" {
#     bucket         = "arvind-paved-road-ai-tfstate"
#     key            = "envs/dev/terraform.tfstate"
#     region         = "us-east-1"
#     dynamodb_table = "terraform-locks"
#     encrypt        = true
#   }
# }
#
# For a first-day setup, we use local state (default). Migrate to S3
# once the bucket is bootstrapped separately.
# -----------------------------------------------------------------------------
