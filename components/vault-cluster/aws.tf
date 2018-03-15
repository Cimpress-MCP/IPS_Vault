provider "aws" {
  region = "${var.aws_region}"
  profile = "${var.aws_profile}"
}

data "aws_ami" "amazon_linux" {
  most_recent = true

  owners = ["${var.aws_account_id}"]

  filter {
    name   = "name"
    values = ["vault-consul-amazon-linux-*"]
  }
}
