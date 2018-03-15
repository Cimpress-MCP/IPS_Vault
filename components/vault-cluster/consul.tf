module "consul_servers" {
  # we no longer use the public 
  source = "git::https://github.com/hashicorp/terraform-aws-consul.git//modules/consul-cluster?ref=v0.0.5"
  
  cluster_name  = "${var.cluster_name}-consul"
  cluster_size  = 3
  instance_type = "t2.micro"

  # EC2 instances use these tags to automatically discover nodes
  cluster_tag_key   = "${var.cluster_name}-consul"
  cluster_tag_value = "${var.cluster_name}"

  ami_id = "${data.aws_ami.amazon_linux.image_id}"

  vpc_id     = "${module.vpc.vpc_id}"
  subnet_ids = "${module.vpc.private_subnets}"
  //associate_public_ip_address = true

  allowed_ssh_cidr_blocks     = ["${var.my_ip}"]
  allowed_inbound_cidr_blocks = ["${var.vpc_network}"]
  user_data                   = "${data.template_file.user_data_consul_cluster.rendered}"

  ssh_key_name = "${var.vault_ssh_key_name}"

/*
  cluster_extra_tags = [
    {
      key = "Owner"
      value = "${var.squad_name}"
      propagate_at_launch = true
    },
    {
      key = "Squad Name"
      value = "${var.squad_name}"
      propagate_at_launch = true
    },
    {
      key = "Environment"
      value = "${var.environment}"
      propagate_at_launch = true
    }
  ]
*/
}

# ---------------------------------------------------------------------------------------------------------------------
# THE USER DATA SCRIPT THAT WILL RUN ON EACH VAULT SERVER WHEN IT'S BOOTING
# This script will configure and start Vault
# ---------------------------------------------------------------------------------------------------------------------

data "template_file" "user_data_consul_cluster" {
  template = "${file("${path.module}/templates/user-data-consul.sh")}"

  vars {
    consul_cluster_tag_key   = "${var.cluster_name}-consul"
    consul_cluster_tag_value = "${var.cluster_name}"
  }
}
