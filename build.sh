#!/usr/bin/env bash

readonly SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
readonly SCRIPT_NAME="$(basename "$0")"

TERRAFORM_ARGS=""

# load configs
source $SCRIPT_DIR/config.shlib

## initialize color codes for nice output
red='\e[1;31m%s\e[0m\n'
green='\e[1;32m%s\e[0m\n'
yellow='\e[1;33m%s\e[0m\n'
blue='\e[1;34m%s\e[0m\n'
magenta='\e[1;35m%s\e[0m\n'
cyan='\e[1;36m%s\e[0m\n'

function log {
  local readonly level="$1"
  local readonly message="$2"
  local readonly timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  >&2 echo -e "${timestamp} [${level}] [$SCRIPT_NAME] ${message}"
}

function log_info {
  local readonly message="$1"
  log "INFO" "$message"
  printf "$blue" "$message"
}

function log_warn {
  local readonly message="$1"
  log "WARN" "$message"
  printf "$yellow" "$message"
}

function log_error {
  local readonly message="$1"
  log "ERROR" "$message"
  printf "$red" "$message"
}

function assert_is_installed {
  local readonly name="$1"

  if [[ ! $(command -v ${name}) ]]; then
    log_error "The binary '$name' is required by this script but is not installed or in the system's PATH."
    exit 1
  fi
}

function tf_init() {
    terraform init -upgrade=true $TERRAFORM_ARGS > /dev/null
    if [ $? -ne 0 ]; then
        log_error "Error: Terraform initialzation failed"
        exit 1
    fi
}

function tf_apply() {
    terraform apply --auto-approve $TERRAFORM_ARGS
    if [ $? -ne 0 ]; then
        log_error "Error: Terraform apply failed"
        exit 1
    fi
}

function tf_destroy() {
    terraform destroy -force $TERRAFORM_ARGS
    if [ $? -ne 0 ]; then
        log_error "Error: Terraform did not destroy properly"
        exit 1
    fi
}

function build_ami() {
    cd $SCRIPT_DIR/components/vault-ami
    log_info "Building VPC for packer AMI generation"

    ## terraform will build the VPC
    tf_init
    tf_apply

    export TF_VAR_vpc_id=`terraform output vpc_id 2> /dev/null`
    export TF_VAR_subnet_id=`terraform output public_subnets 2> /dev/null | tail -1`

    packer build vault-consul.json
    if [ $? -ne 0 ]; then
        log_error "Error: Packer build failed"
        exit 1
    fi
    log_info "Tearing down VPC for packer (this may take some time)"
    tf_destroy
    cd ../..
}

function build_cluster_vpc() {
    cd $SCRIPT_DIR/components/vault-vpc 
    log_info "Building VPC for Vault Cluster"
    tf_init
    tf_apply
    export TF_VAR_vpc_id=$(terraform output vpc_id 2> /dev/null)
    export TF_VAR_vpc_public_subnets=$(terraform output vpc_public_subnets 2> /dev/null)
    export TF_VAR_vpc_private_subnets=$(terraform output vpc_private_subnets 2> /dev/null)
    cd ../..
}

function build_cluster() {
    log_info "Creating Vault Cluster $TF_VAR_cluster_name"
    cd $SCRIPT_DIR/components/vault-cluster
    tf_init
    tf_apply
    log_info "Cluster has build successfully"
    cd ../..
}

function teardown_manual() {
    s3_name="${TF_VAR_cluster_name}-vault-storage"

    log_info "Destroying S3 bucket $s3_name"
    objs=$(aws s3api list-objects --bucket $s3_name --query 'Contents[*].Key' --output text)
    for o in $objs; do
        aws s3api delete-object --bucket $s3_name --key "${o}"
    done

    log_info "Destroying data in Parameter Store"
    params=$(aws ssm describe-parameters --filters "Key=Name,Values=${TF_VAR_cluster_name}." --query 'Parameters[*].Name' --output text)
    for p in $params; do
        aws ssm delete-parameter --name "${p}"
    done
}

function teardown_vault_vpc() {
    log_info "Destroying Vault Cluster VPC $TF_VAR_cluster_name"
    cd $SCRIPT_DIR/components/vault-vpc
    tf_init
    tf_destroy
    cd ../..
}

function teardown_cluster() {
    log_info "Destroying Vault cluster $TF_VAR_cluster_name"
    cd $SCRIPT_DIR/components/vault-cluster
    tf_init
    tf_destroy
    cd ../..
    if [ "$DEDICATED_VPC" == 1 ]; then
        teardown_vault_vpc
    fi
}

function teardown_packer() {
    log_info "Destroying packer infrastructure"
    cd $SCRIPT_DIR/components/vault-ami
    tf_init
    tf_destroy
    cd ../..
}

function read_config() {
    export TF_VAR_aws_region="$(config_get aws_region)"
    export TF_VAR_cluster_name="$(config_get cluster_name)"
    export TF_VAR_dns_name="$(config_get dns_name)"
    export TF_VAR_dns_zone="$(config_get dns_zone)"
    export TF_VAR_vault_ssh_key_name="$(config_get vault_ssh_key_name)"
    export TF_VAR_aws_account_id="$(config_get aws_account_id)"
    export TF_VAR_squad_name="$(config_get squad_name)"
    export TF_VAR_environment="$(config_get environment)"
    export TF_VAR_kms_key_alias="$(config_get kms_key_alias)"
    export TF_VAR_aws_profile="$(config_get aws_profile)"
    export AWS_PROFILE=$TF_VAR_aws_profile
    export DEDICATED_VPC="$(config_get dedicated_vpc)"
    export TF_VAR_vpc_id="$(config_get vpc_id)"
}

function write_config() {
    cat > config.cfg << EOF
aws_region=$TF_VAR_aws_region
cluster_name=$TF_VAR_cluster_name
dns_name=$TF_VAR_dns_name
dns_zone=$TF_VAR_dns_zone
vault_ssh_key_name=$TF_VAR_vault_ssh_key_name
aws_account_id=$TF_VAR_aws_account_id
squad_name=$TF_VAR_squad_name
environment=$TF_VAR_environment
kms_key_alias=$TF_VAR_kms_key_alias
aws_profile=$TF_VAR_aws_profile
dedicated_vpc=$DEDICATED_VPC
vpc_id=$TF_VAR_vpc_id
EOF
}

function update_kms_alias_role() {
    cd $SCRIPT_DIR/components/vault-cluster
    #get role_id from terraform
    role_id=$(terraform output vault_cluster_role_arn | cut -d '/' -f 2)
    cd ../..
    # find our keyID from AWS
    key=$(aws kms list-aliases | jq '.[][]' | grep -A 1 ${TF_VAR_kms_key_alias} | grep TargetKeyId | cut -d ":" -f 2 | sed s/\"//g | tr -d '[:space:]')

    #generate template, remove newlines and then remove all spaces.
    policy=$(cat ./templates/kms.tmpl | sed s/ACCOUNT_ID/$TF_VAR_aws_account_id/g | sed s/VAULT_ROLE_ID/$role_id/g | sed s/KEY_ID/$key/g | tr '\n' ' ')
    policy="${policy//[[:space:]]/}"

    ## --cli-input-json file://test-key-policy.json
    aws kms put-key-policy --key-id $key --policy-name "default" --cli-input-json $policy
}

function help() {
    printf "$green" "----- build.sh ----"
    printf "$green" "- utility script to build and deploy a vault cluster "
    printf "$green" "Options:"
    printf "$green" " --cluster=CLUSTER_NAME     (Name of Vault Clster, ex: vault-dev)"
    printf "$green" " --dns_name=DNS_NAME        (DNS Entry for Cluster.  AWS Cert must exist before running script, ex: dev.ips.cimpress.io)"
    printf "$green" " --env=ENVIRONMENT          (Environment name to build)"
    printf "$green" " --key=KMS_KEY              (KMS Key alias to use for encryption)"
    printf "$green" " --profile=AWS_PROFILE      (AWS Profile to use)"
    printf "$green" " --region=AWS_REGION        (AWS Region to deploy to, ex: eu-west-1)"
    printf "$green" " --ssh=SSH_KEY              (SSH Key used to access nodes, ex: AWS_IPS_Vault)"
    printf "$green" " --squad=SQUAD              (Squad name to tag instances with)"
    printf "$green" " --zone=DNS_ZONE            (Route 53 zone to add cluster to, ex: cimpress.io)"
    printf "$green" " --no-ami                   (Do not build AMI, useful for quick cluster rebuilds)"
    printf "$green" " --dedicated_vpc            (Deploy Vault in a dedicated VPC)"
    printf "$green" " --destroy                  (Must specify ONE of the flag below)"
    printf "$green" "   --all                    (Teardown and destroy your vault cluster and data)"
    printf "$green" "   --infra                  (Teardown and destroy your vault cluster only)"
    printf "$green" "   --data                   (Destroy your vault data only)"

    exit 0
}

function check_parameters() {
    ## reset in case getops has been used in another script
    OPTIND=1

    # loop through and find our options
    for i in "$@"
    do
    case $i in
        --cluster=*)
        TF_VAR_cluster_name="${i#*=}"
        export TF_VAR_cluster_name=$TF_VAR_cluster_name
        shift
        ;;
        --dedicated_vpc)
        DEDICATED_VPC=true
        ;;
        --dns_name=*)
        TF_VAR_dns_name="${i#*=}"
        export TF_VAR_dns_name=$TF_VAR_dns_name
        shift
        ;;
        --env=*)
        TF_VAR_environment="${i#*=}"
        export TF_VAR_environment=$TF_VAR_environment
        shift
        ;;
        --key=*)
        TF_VAR_kms_key_alias="${i#*=}"
        export TF_VAR_kms_key_alias=$TF_VAR_kms_key_alias
        shift
        ;;
        --profile=*)
        TF_VAR_aws_profile="${i#*=}"
        export TF_VAR_aws_profile=$TF_VAR_aws_profile
        shift
        ;;
        --region=*)
        TF_VAR_aws_region="${i#*=}"
        export TF_VAR_aws_region=$TF_VAR_aws_region
        shift # past argument=value
        ;;
        --ssh=*)
        TF_VAR_ssh_key="${i#*=}"
        export TF_VAR_vault_ssh_key_name=$TF_VAR_ssh_key
        shift
        ;;
        --squad=*)
        TF_VAR_squad_name="${i#*=}"
        export TF_VAR_squad_name=$TF_VAR_squad_name
        shift
        ;;
        --zone=*)
        TF_VAR_dns_zone="${i#*=}"
        export TF_VAR_dns_zone=$TF_VAR_dns_zone
        shift
        ;;
        -h|-?|--help)
        help
        exit 0
        ;;
        --debug)
        set -x
        ;;
        --no-ami)
        NO_AMI=1
        ;;  
        --destroy)
        DESTROY=1
        ;;
        --all)
        D_ALL=1
        ;;
        --data)
        D_DATA=1
        ;;
        --infra)
        D_INFRA=1
        ;;
        *)
        log_error "Unknown option given: " $i
        exit 1
        ;;

    esac
    done

    # ask user for input if not set in environment or on command line options
    if [ "$TF_VAR_aws_region" == "__UNDEFINED__" ]; then
        printf "$green" "Which AWS region do you want to deploy vault?: "
        read AWS_REGION
        export TF_VAR_aws_region=$AWS_REGION
        echo ""
    fi

    if [ "$TF_VAR_aws_profile" == "__UNDEFINED__" ]; then
        printf "$green" "Which AWS profile do you want to use?: "
        read AWS_PROFILE
        export TF_VAR_aws_profile=$AWS_PROFILE
        export AWS_PROFILE=$AWS_PROFILE
        echo ""
    fi

    if [ "$TF_VAR_cluster_name" == "__UNDEFINED__" ]; then
        printf "$green" "What is the name of your vault cluster?: "
        read VAULT_CLUSTER_NAME
        export TF_VAR_cluster_name=$VAULT_CLUSTER_NAME
        echo ""
    fi

    if [ "$TF_VAR_dns_name" == "__UNDEFINED__" ]; then
        printf "$green" "What is the DNS name for this cluster? (ex: vault.ips.cimpress.io): "
        read VAULT_DNS
        export TF_VAR_dns_name=$VAULT_DNS
        echo ""
    fi

    if [ "$TF_VAR_dns_zone" == "__UNDEFINED__" ]; then
        printf "$green" "What Route 53 zone should we add this cluster to? (example, ips.cimpress.io): "
        read TF_VAR_dns_zone
        export TF_VAR_dns_zone=$TF_VAR_dns_zone
        echo ""
    fi

    if [ "$TF_VAR_vault_ssh_key_name" == "__UNDEFINED__" ]; then 
        printf "$green" "What SSH key will be used to access the nodes?:"
        read TF_VAR_vault_ssh_key_name
        export TF_VAR_vault_ssh_key_name=$TF_VAR_vault_ssh_key_name
        echo ""
    fi

    if [ "$TF_VAR_environment" == "__UNDEFINED__" ]; then 
        printf "$green" "What environment are you building? (Dev, Prod):"
        read TF_VAR_environment
        export TF_VAR_environment=$TF_VAR_environment
        echo ""
    fi

    if [ "$TF_VAR_squad_name" == "__UNDEFINED__" ]; then 
        printf "$green" "What is the name of the squad that manages this cluster?:"
        read TF_VAR_squad_name
        export TF_VAR_squad_name=$TF_VAR_squad_name
        echo ""
    fi

    if [ "$TF_VAR_kms_key_alias" == "__UNDEFINED__" ]; then 
        printf "$green" "What is the alias of your KMS key to use for encryption?:"
        read TF_VAR_kms_key_alias
        export TF_VAR_kms_key_alias=$TF_VAR_kms_key_alias
        echo ""
    fi

    if [ "$TF_VAR_aws_account_id" == "__UNDEFINED__" ]; then
        ## find ACCOUNT ID by querying AWS
        AWS_ACCOUNT_ID=`aws iam get-user --profile $TF_VAR_aws_profile --output json \
                | awk '/arn:aws:/{print $2}' \
                | grep -Eo '[[:digit:]]{12}'`

        if  [ "$?" == "1" ]; then
            log_error "Could not communicate to AWS.  Please check your AWS client configuration."
            exit 1
        fi
        export TF_VAR_aws_account_id=$AWS_ACCOUNT_ID
    fi

    if [ "$DEDICATED_VPC" == "__UNDEFINED__" ]; then
        printf "$green" "Do you wish to deploy Vault in a dedicated VPC (n indicates allow user to select VPC) (y/n):"
        WAIT_FOR_VPCSELECT=1
        read DEDICATED_VPC
        while [ $WAIT_FOR_VPCSELECT == "1" ]; do
            case $DEDICATED_VPC in 
                y|Y)
                DEDICATED_VPC=1
                WAIT_FOR_VPCSELECT=0
                ;;
                n|N)
                DEDICATED_VPC=0
                WAIT_FOR_VPCSELECT=0
                ;;
                *)
                printf "$green" "Sorry, your entry was not accepted, please try again (y/n):"
                read DEDICATED_VPC
            esac
        done
    fi

}

#####  MAIN #####
assert_is_installed "terraform"
assert_is_installed "packer"
assert_is_installed "aws"
assert_is_installed "jq"
assert_is_installed "go"

read_config

check_parameters $@

## discover IP address we are coming from
IP=$(curl --silent http://whatismyip.akamai.com/)
if [[ $IP =~ .*:.* ]]; then
    export TF_VAR_my_ip="0.0.0.0/0"
else
    export TF_VAR_my_ip=$IP/32
fi

write_config

if [ "$DESTROY" == 1 ]; then
    if [ "$D_ALL" == 1 ] && [[ "$D_INFRA" == 1  || "$D_DATA" == 1 ]]; then
        log_error "Cannot specify --all with --data and/or -infra"
        exit 1
    elif [  "$D_INFRA" == 1 ] && [[ "$D_DATA" == 1 || "$D_ALL" == 1 ]]; then
        log_error "Cannot specify --infra with --data and/or --all"
        exit 1
    elif [  "$D_DATA" == 1 ] && [[ "$D_INFRA" == 1 || "$D_ALL" == 1 ]]; then
        log_error "Cannot specify --data with --infra and/or --all"
        exit 1
    fi

    if [ "$D_ALL" == 1 ]; then
        # teardown_packer
        teardown_manual
        teardown_cluster
    elif [ "$D_INFRA" == 1 ]; then
        # teardown_packer
        teardown_cluster
    elif [ "$D_DATA" == 1 ]; then
        teardown_manual
    else
        log_error "You must specify one of --data --infra or --all"
        exit 1
    fi

    exit $?
fi

if [ -z "$NO_AMI" ]; then
    build_ami
fi

if [ "$DEDICATED_VPC" == 1 ]; then
    build_cluster_vpc
else
    cd vpcselect 
    rm -f vpcid.txt
    rm -f vpcnetwork.txt

    go get
    go build 
    if [ $? -ne 0 ]; then
        log_error "Error: could not build vpcselect?"
        exit 1
    fi
    ./vpcselect 
    if [ $? -ne 0 ]; then
        log_error "Error: vpcselect failed?"
        exit 1
    fi
    export TF_VAR_vpc_id=$(cat vpcid.txt)
    if [ -z "$TF_VAR_vpc_id" ]; then
        log_error "Could not find VPC information, please check your aws configuration."
        exit 1
    fi
    export TF_VAR_vpc_network=$(cat vpcnetwork.txt)
    public_subnets=$(cat publicsubnets.txt)
    private_subnets=$(cat privatesubnets.txt)

    cat > $SCRIPT_DIR/vars.tfvars << EOF
vpc_public_subnets=[$public_subnets]
vpc_private_subnets=[$private_subnets]
EOF
    TERRAFORM_ARGS="-var-file=$SCRIPT_DIR/vars.tfvars"
    write_config
    cd ..
fi

build_cluster
update_kms_alias_role

log_info "Your cluster is now available at https://$TF_VAR_dns_name"

## exit with last exit code from Terraform
exit $?
