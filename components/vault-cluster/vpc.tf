module "vpc" {
  source = "github.com/jcharette/terraform-vpc.git"

  vpc_name       = "${var.cluster_name}-vpc"
  vpc_cidr_block = "${var.vpc_network}"

  map_public_ip_on_launch = true
}
