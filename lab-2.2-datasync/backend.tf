terraform {
  backend "s3" {
    bucket = "cdem01-tfstate"
    key    = "lab-2.2-datasync/terraform.tfstate"
    region = "eu-west-1"
  }
}
