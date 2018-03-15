module "vpc" {
  source = "github.com/jcharette/terraform-vpc.git"

  vpc_name       = "packer-${var.cluster_name}-vpc"
  vpc_cidr_block = "192.168.16.0/24"

  aws_region = "${var.aws_region}"
  
  map_public_ip_on_launch = true
  create_private_subnets = false
  enable_dns_support = true
  tags {
    "Environment" = "Packer Builder"
  }
}
