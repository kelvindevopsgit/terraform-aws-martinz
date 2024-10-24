variable "aws_region" {
  description = "The AWS region to deploy resources"
  type        = string
}

variable "vpc_cidr_block" {
  description = "The CIDR block for the VPC"
  type        = string
}

variable "public_subnet_cidr_block" {
  description = "The CIDR block for the public subnet"
  type        = string
}

variable "private_subnet_cidr_block" {
  description = "The CIDR block for the private subnet"
  type        = string
}

variable "private_subnet_2_cidr_block" {
  description = "The CIDR block for the second private subnet"
  type        = string
}
