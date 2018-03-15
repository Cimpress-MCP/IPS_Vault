
## VPC Info
output "vpc_id" {
  value = "${module.vpc.vpc_id}"
}

output "public_subnets" {
  value = "${module.vpc.public_subnets}"
}

output "private_subnets" {
  value = "${module.vpc.private_subnets}"
}

output "vault_cluster_role_arn" {
  value = "${module.vault_cluster.iam_role_arn}"
}
