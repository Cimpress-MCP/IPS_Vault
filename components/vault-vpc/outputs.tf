output "vpc_id" {
  value = "${module.vpc.vpc_id}"
}

output "vpc_public_subnets" {
  value = "${module.vpc.public_subnets_str}"
}

output "vpc_private_subnets" {
  value = "${module.vpc.private_subnets_str}"
}
