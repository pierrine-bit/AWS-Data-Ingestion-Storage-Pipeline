terraform {
  backend "s3" {
    bucket = "cdem01-tfstate"
    key    = "lab-2.3-kinesis/terraform.tfstate"
    region = "eu-west-1"
  }
}
