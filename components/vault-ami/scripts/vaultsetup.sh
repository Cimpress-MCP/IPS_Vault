#!/usr/bin/env bash

# This script is used to automate the initialization and unsealing of Vault on an AWS EC2 node.
#
# Within an unitialized instance, it will initialize vault and then store the keys in 
# Parameter store using KMS encryption.
#
# On nodes where the vault has been iniialized, it will read the decrypted keys from Paramter Store
# and use the keys to unseal the node.
#


export VAULT_ADDR=http://localhost:8200
initOutput="/home/ec2-user/vault-init.txt"

#ask EC2 metadata for our cluster name
INSTANCE_ID="`wget -qO- http://instance-data/latest/meta-data/instance-id`"
REGION="`wget -qO- http://instance-data/latest/meta-data/placement/availability-zone | sed -e 's:\([0-9][0-9]*\)[a-z]*\$:\\1:'`"

#get cluster and KMS information from EC2 Tags.
KMS_TAG_NAME="KMS Alias"
KMS_ALIAS="`aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=$KMS_TAG_NAME" --region $REGION --output=text | cut -f5`"

CLUSTER_TAG_NAME="Vault Cluster"
CLUSTER_NAME="`aws ec2 describe-tags --filters "Name=resource-id,Values=$INSTANCE_ID" "Name=key,Values=$CLUSTER_TAG_NAME" --region $REGION --output=text | cut -f5`"

export CHAMBER_KMS_KEY_ALIAS=$KMS_ALIAS

echo "using KMS_KEY alias of $KMS_ALIAS"

function wait_for_vault_start() {
	## wait for vault to start
	while [ -z "`netstat -tln | grep 8200`" ]; do
		echo "Waiting for Vault to start"
		sleep 1
	done
	echo "Vault has started, we're ready to initialize or unseal"
}

# write a key to paramater store
## argv1 = keyname
## argv2 = keyvalue
function write_key() {
	if [ -z "$1" ]; then
		echo "ERROR: Cannot write key with no name."
		return 1
	fi	
	keyName=$1
	
	if [ -z "$2" ]; then
		echo "ERROR:  Cannot write key $keyName with no value"
		return 1
	fi
	keyValue=$2

	# write to Chamber, hope it comes back
	chamber write $CLUSTER_NAME $keyName $keyValue
	echo "Writing $keyName for cluster $CLUSTER_NAME with value $keyValue"
	if [ $? -ne 0 ]; then
		printf "$red" "Error: Chamber write failed?"
		return 1
	fi

	echo "verifying read key of $keyName"
	read_key $keyName
	while [ "$keyVal" != "$keyValue" ]; do
		## verify write
		echo "ERROR: Could not read key back from parameter store?? Trying write again"
		chamber write $CLUSTER_NAME $keyName $keyValue
		sleep 1
		read_key $keyName
	done
	echo "$keyName written as $keyVal to chamber"

	return 0
}

# argv1 = keyName
# sets GLOBAL keyVal of return string from paramater store
function read_key() {
	if [ -z "$1" ]; then
		echo "ERROR: Cannot read key with no name."
		return ""
	fi
	local keyName=$1
	local keys=$(chamber export $CLUSTER_NAME)
	keyVal=""
	if [ "$keys" == "{}" ]; then
		echo "ERROR: chamber could not find any data for $CLUSTER_NAME"
		return
	fi

	case $keyName in
		"key1")
			keyVal=$(echo $keys | jq -r '.key1')
			;;
		"key2")
			keyVal=$(echo $keys | jq -r '.key2')
			;;
		"key3")
			keyVal=$(echo $keys | jq -r '.key3')
			;;
		"key4")
			keyVal=$(echo $keys | jq -r '.key4')
			;;
		"key5")
			keyVal=$(echo $keys | jq -r '.key5')
			;;
		"roottoken")
			keyVal=$(echo $keys | jq -r '.roottoken')
			;;
		"status")
			keyVal=$(echo $keys | jq -r '.status')
			;;
		"node")
			keyVal=$(echo $keys | jq -r '.node')
			;;
		*)
			echo "could not find key $keyName"
			;;
	esac			
}

# attempt to read from Parameter store and unseal Vault.
function unseal_vault() {
	keyVal=""
	read_key "key1"
	while [ $keyVal == "" ]; do
		echo "waiting for key1 in Parameter Store"
		sleep 5
		read_key "key1"
	done
	echo "Unsealing with Key1"
	/usr/local/bin/vault operator unseal $keyVal

	keyVal=""
	read_key "key2"
	while [ $keyVal == "" ]; do
		echo "waiting for key2 in Parameter Store"
		sleep 5
		read_key "key2"
	done
	echo "Unsealing with Key2"
	/usr/local/bin/vault operator unseal $keyVal
	
	keyVal=""
	read_key "key3"
	while [ $keyVal == "" ]; do
		echo "waiting for key3 in Parameter Store"
		sleep 5
		read_key "key3"
	done
	echo "Unsealing with Key3"
	/usr/local/bin/vault operator unseal $keyVal
}

# initialize vault if possible.
function initialize_vault() {
	initalize_status=$(chamber export $CLUSTER_NAME | grep status)
	if [ -z "$initialize_status" ]; then
		# notify other nodes we are starting to initialize
		write_key status "initializing"
		write_key node $INSTANCE_ID

		/opt/vault/bin/vault operator init  > $initOutput
		# vault init likes to put escape colors in the output.. we don't like that :)
		sed --in-place -r "s/\x1b\[([0-9]{1,2}(;[0-9]{1,2})?)?m//g" $initOutput

		## loop through keys in init output and write them to chamber
		keys=$(grep Key $initOutput | cut -d ' ' -f 4)
		keyarray=($keys)

		keypos=0
		for i in "${keyarray[@]}"
		do
			keypos=$((keypos+1))
			paramKey=key$keypos
			write_key $paramKey $i
		done

		# save the root token as well, so provisioner can find it.
		token=$(grep Token $initOutput | cut -d ' ' -f 4)
		write_key roottoken $token

		# notify the other nodes we are finished
		write_key status "ready"
	fi
}

# loop to wait for ready signal from initialzing node
function wait_for_ready() {
	read_key status
	while [ "$keyVal" != "ready" ]; do
		read_key node
		echo "Waiting for ready signal in paramater store, instance $keyVal is initializing."
		sleep .$[ ( $RANDOM % 4 ) + 1 ]s
		read_key status
	done		
}

#### MAIN ######

echo "Sleeping 1-4 seconds to avoid deadlocks of other init."
sleep .$[ ( $RANDOM % 4 ) + 1 ]s

wait_for_vault_start
initialize_vault
wait_for_ready

# unseal this node
status=$(/usr/local/bin/vault status | grep Sealed | grep true | cut -d ' ' -f 1)
while [ "$status" == "Sealed" ]; do
	unseal_vault
	sleep 2
	status=$(/usr/local/bin/vault status | grep Sealed | grep true | cut -d ' ' -f 1)
done
