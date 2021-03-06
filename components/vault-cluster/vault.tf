module "vault_cluster" {
  source = "git::https://github.com/Cimpress-MCP/terraform-aws-vault.git//modules/vault-cluster?v0.10.0"

  kms_key_alias = "${var.kms_key_alias}"

  cluster_name  = "${var.cluster_name}"
  cluster_size  = "${var.vault_cluster_size}"
  instance_type = "${var.vault_instance_type}"

  ami_id    = "${data.aws_ami.amazon_linux.image_id}"
  user_data = "${data.template_file.user_data_vault_cluster.rendered}"

  enable_s3_backend = true
  s3_bucket_name    = "${var.cluster_name}-vault-storage"

  vpc_id                      = "${var.vpc_id}"
  subnet_ids                  = ["${var.vpc_public_subnets}"]
  associate_public_ip_address = true

  allowed_inbound_cidr_blocks = ["${var.my_ip}"]

  allowed_ssh_cidr_blocks            = ["${var.my_ip}"]
  allowed_inbound_security_group_ids = ["${module.vault_elb.load_balancer_security_group_id}"]

  ssh_key_name = "${var.vault_ssh_key_name}"
  user_data    = "${data.template_file.user_data_vault_cluster.rendered}"

  cluster_extra_tags = [
    {
      key                 = "Vault Cluster"
      value               = "${var.cluster_name}"
      propagate_at_launch = true
    },
    {
      key                 = "Owner"
      value               = "Terraform"
      propagate_at_launch = true
    },
    {
      key                 = "Creator"
      value               = "Terraform"
      propagate_at_launch = true
    },
    {
      key                 = "Squad Name"
      value               = "${var.squad_name}"
      propagate_at_launch = true
    },
    {
      key                 = "Environment"
      value               = "${var.environment}"
      propagate_at_launch = true
    },
    {
      key                 = "KMS Alias"
      value               = "${var.kms_key_alias}"
      propagate_at_launch = true
    },
  ]
}

# ---------------------------------------------------------------------------------------------------------------------
# ATTACH IAM POLICIES FOR CONSUL
# To allow our Vault servers to automatically discover the Consul servers, we need to give them the IAM permissions from
# the Consul AWS Module's consul-iam-policies module.
# ---------------------------------------------------------------------------------------------------------------------

module "consul_iam_policies_servers" {
  source = "github.com/hashicorp/terraform-aws-consul.git//modules/consul-iam-policies?ref=v0.3.3"

  iam_role_id = "${module.vault_cluster.iam_role_id}"
}

data "template_file" "user_data_vault_cluster" {
  template = "${file("${path.module}/templates/user-data-vault.sh")}"

  vars {
    aws_region               = "${var.aws_region}"
    s3_bucket_name           = "${var.cluster_name}-vault-storage"
    consul_cluster_tag_value = "${var.cluster_name}-consul"
    consul_cluster_tag_key   = "Name"
  }
}
