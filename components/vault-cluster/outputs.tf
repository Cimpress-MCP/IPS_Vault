output "vault_cluster_role_arn" {
  value = "${module.vault_cluster.iam_role_arn}"
}
