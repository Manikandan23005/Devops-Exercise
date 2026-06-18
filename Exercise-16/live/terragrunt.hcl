locals {
  aws_region = "us-east-1"
}

remote_state {
  backend = "local"
  config = {
    path = "${get_terragrunt_dir()}/../../../terraform.tfstate"
  }
}
