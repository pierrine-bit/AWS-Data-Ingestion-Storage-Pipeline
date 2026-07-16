terraform {
  backend "s3" {
    bucket = "cdem01-tfstate"
    key    = "lab-2.1-s3/terraform.tfstate"
    region = "eu-west-1"
  }
}
