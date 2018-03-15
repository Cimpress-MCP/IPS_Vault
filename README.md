# Cimpress Vault

This repo contains a pattern for deploying a [Vault](https://www.vaultproject.io/) cluster on 
[AWS](https://aws.amazon.com/) using [Terraform](https://www.terraform.io/). Vault is an open source tool for managing
secrets. This Module uses [S3](https://aws.amazon.com/s3/) as a [storage 
backend](https://www.vaultproject.io/docs/configuration/storage/index.html) and a [Consul](https://www.consul.io) 
server cluster as a [high availability backend](https://www.vaultproject.io/docs/concepts/ha.html):

![Vault architecture](https://github.com/hashicorp/terraform-aws-vault/blob/master/_docs/architecture.png?raw=true)

This Module includes:

* [vault-ami]:  This module will build a custom AMI within AWS using Packer (https://www.packer.io).

* [vault-cluster]: This module will build your vault cluster using the built AMI noted above.

## Architecture

This pattern will create an isolated VPC based Vault cluster in AWS.  All communication to the Vault nodes is through a Secured HTTPS connection using AWS ELB's and managed certificates. Secured connections are terminated at the ELB and passed via HTTP to the Vault node directly.  Consul is used as a directory service for Vault nodes to determine the active node and used for all Vault storage.

## Prerequisites

Before running the build script, you should have the following information and components configured within AWS.

* AWS Cli installed and configured for your environment

* AWS Managed SSL Cert with your Cluster's DNS name

* AWS KMS Key generated in your account with an alias defined for your cluster

* AWS SSH Key installed within the region you are deploying

* Route 53 DNS services configured for your hosted domain

* Packer(https://www.packer.io/intro/index.html) installed and in your path

* Terraform(https://www.terraform.io/downloads.html) installed and in your path

To deploy the Vault cluster:

1. Create your AWS Managed SSL certificate with your domain name that you assign to the cluster.  

2. Create your AWS KMS Key with the same name as your cluster.

3. Create a AWS SSH key pair for remote access to your cluster's nodes.

4. Run build.sh on your system.  Build.sh has two methods of execution, either interactive (by just running build.sh) or using command line options.

5. After build.sh completes, log into the AWS portal and you will see nodes being created.  Two types of nodes are provisioned.  The first will be consul nodes, running on t2.micros.  These nodes are used by consul to provide backend HA DNS services for Vault.  The other nodes are vault API nodes, running on t2.medium.  These are the nodes that Vault services are running on.

## Vault Initialization and Unsealing

After your cluster has been deployed, vault will initialize itself and store its keys, encrypted with your KMS key, within AWS Parameter store.  These keys will be automatically decrypted by other nodes and used to unseal vault.  

## Provisioning your Users and Policies

A policy provisioning tool has been provided within this module to allow you to configure your Vault instance users and policies.  The tool uses the Hashicorp JSON api (https://www.vaultproject.io/api/index.html) to make changes to your environment. Samples have been provided on how to configure MFA access with Duo and setting up a user's access into vault. 

The tool is located in the /provisioner folder of this module. JSON layout is found /provisioner/data.

Copyright &copy; 2017 Cimpress, Inc.