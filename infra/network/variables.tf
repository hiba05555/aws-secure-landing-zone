variable "aws_region" {
  default     = "eu-west-1"
}


variable "aws_profile" {
  default = "terraform-deployer"
}

variable "vpc_cidr" {
    default = "10.0.0.0/16"
}