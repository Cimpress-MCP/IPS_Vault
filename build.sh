#!/usr/bin/env bash

SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"

# load configs
source $SCRIPT_DIR/config.shlib

## initialize color codes for nice output
red='\e[1;31m%s\e[0m\n'
green='\e[1;32m%s\e[0m\n'
yellow='\e[1;33m%s\e[0m\n'
blue='\e[1;34m%s\e[0m\n'
magenta='\e[1;35m%s\e[0m\n'
cyan='\e[1;36m%s\e[0m\n'

function build_ami() {
    cd $SCRIPT_DIR/components/vault-ami
    printf "$blue" "Building VPC for packer AMI generation"
    ## terraform will build the VPC and SSL certs
    terraform init -upgrade=true >/dev/null
    if [ $? -ne 0 ]; then
        printf "$red" "Error: Terraform initialzation failed"
        exit 1
    fi
    terraform apply -auto-approve > /dev/null

    export TF_VAR_vpc_id=`terraform output vpc_id 2> /dev/null`
    export TF_VAR_subnet_id=`terraform output public_subnets 2> /dev/null | tail -1`

    packer build vault-consul.json
    if [ $? -ne 0 ]; then
        printf "$red" "Error: Packer build failed"
        exit 1
    fi
    printf "$blue" "Tearing down VPC for packer (this may take some time)"
    terraform destroy -force >/dev/null
    if [ $? -ne 0 ]; then
        printf "$red" "Error: VPC did not tear down properly"
        exit 1
    fi
    cd ../..
}

function build_cluster() {
    printf "$blue" "Creating Vault Cluster $TF_VAR_cluster_name"
    cd $SCRIPT_DIR/components/vault-cluster
    terraform init -upgrade=true >/dev/null
    if [ $? -ne 0 ]; then
        printf "$red" "Error: Terraform initialzation failed"
        exit 1
    fi

    terraform plan -out plan.out &>/dev/null

    terraform apply -auto-approve plan.out
    if [ $? -ne 0 ]; then
        printf "$red" "Error: Terraform apply failed"
        exit 1
    fi
    rm -rf plan.out
    printf "$blue" "Cluster has build successfully"
    cd ../..
}

function teardown_manual() {
    s3_name="${TF_VAR_cluster_name}-vault-storage"

    printf "$blue" "Destroying S3 bucket $s3_name"
    objs=$(aws s3api list-objects --bucket $s3_name --query 'Contents[*].Key' --output text)
    for o in $objs; do
        aws s3api delete-object --bucket $s3_name --key "${o}"
    done

    printf "$blue" "Destroying data in Parameter Store"
    params=$(aws ssm describe-parameters --filters "Key=Name,Values=${TF_VAR_cluster_name}." --query 'Parameters[*].Name' --output text)
    for p in $params; do
        aws ssm delete-parameter --name "${p}"
    done
}

function teardown_cluster() {
    printf "$blue" "Destroying Vault cluster $TF_VAR_cluster_name"
    cd $SCRIPT_DIR/components/vault-cluster
    terraform destroy -force 
    if [ $? -ne 0 ]; then
        printf "$red" "Error: Terraform Destroy failed"
        exit 1
    fi
    cd ../..
}

function teardown_packer() {
    printf "$blue" "Destroying packer infrastructure"
    cd $SCRIPT_DIR/components/vault-ami
    terraform destroy -force
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
        printf "$red" "Unknown option given: " $i
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
            exit 1
        fi
        export TF_VAR_aws_account_id=$AWS_ACCOUNT_ID
    fi
}

#####  MAIN #####
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
        printf "$red" "Cannot specify --all with --data and/or -infra"
        exit 1
    elif [  "$D_INFRA" == 1 ] && [[ "$D_DATA" == 1 || "$D_ALL" == 1 ]]; then
        printf "$red" "Cannot specify --infra with --data and/or --all"
        exit 1
    elif [  "$D_DATA" == 1 ] && [[ "$D_INFRA" == 1 || "$D_ALL" == 1 ]]; then
        printf "$red" "Cannot specify --data with --infra and/or --all"
        exit 1
    fi

    if [ "$D_ALL" == 1 ]; then
        teardown_packer
        teardown_manual
        teardown_cluster
    elif [ "$D_INFRA" == 1 ]; then
        teardown_packer
        teardown_cluster
    elif [ "$D_DATA" == 1 ]; then
        teardown_manual
    else
        printf "$red" "You must specify one of --data --infra or --all"
        exit 1
    fi

    exit $?
fi

if [ -z "$NO_AMI" ]; then
    build_ami
fi

build_cluster
update_kms_alias_role

## exit with last exit code from Terraform
exit $?
