terraform {
  backend "s3" {
    bucket         = "aims-terraform-state-858507113889-apne2"
    key            = "aims/dev/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "aims-terraform-lock"
    encrypt        = true
    profile        = "aims-terraform"
  }
}