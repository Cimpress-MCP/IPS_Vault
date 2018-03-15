variable "my_ip" {
  type = "string"
}

variable "aws_profile" {
  description = "AWS Profile to use"
  type = "string"
}

variable "aws_region" {
  type = "string"
}

variable "aws_account_id" {
  type = "string"
}

variable "cluster_name" {}

variable "cluster_size" {
  default = 3
}

variable "vault_cluster_size" {
  default = "3"
}

variable "vault_instance_type" {
  default = "t2.medium"
}

variable "force_destroy_s3_bucket" {
  description = "If you set this to true, when you run terraform destroy, this tells Terraform to delete all the objects in the S3 bucket used for backend storage. You should NOT set this to true in production or you risk losing all your data! This property is only here so automated tests of this module can clean up after themselves."
  default     = false
}

variable "vault_ssh_key_name" {}

variable "vpc_network" {
  default = "192.168.16.0/24"
}


variable "dns_zone" {}

variable "dns_name" {}

variable "environment" {}

variable "squad_name" {}

variable "kms_key_alias" {}