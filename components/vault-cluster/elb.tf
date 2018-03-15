data "aws_route53_zone" "default" {
  name = "${var.dns_zone}"
}

module "vault_elb" {
  source = "git::https://github.com/Cimpress-MCP/terraform-aws-vault.git//modules/vault-elb?ref=v0.0.9.1"

  name = "${var.cluster_name}-vault-elb"
  vpc_id = "${module.vpc.vpc_id}"
  allowed_inbound_cidr_blocks = ["0.0.0.0/0"]

  subnet_ids = "${module.vpc.public_subnets}"
  
  create_dns_entry = true
  hosted_zone_id = "${data.aws_route53_zone.default.zone_id}"
  domain_name = "${var.dns_name}"
}