#!/bin/sh

readonly SCRIPT_DIR="$( cd "$( dirname "$0" )" && pwd )"
readonly SCRIPT_NAME="$(basename "$0")"

function log {
  local readonly level="$1"
  local readonly message="$2"
  local readonly timestamp=$(date +"%Y-%m-%d %H:%M:%S")
  >&2 echo -e "${timestamp} [${level}] [$SCRIPT_NAME] ${message}"
}

function log_info {
  local readonly message="$1"
  log "INFO" "$message"
}

function log_warn {
  local readonly message="$1"
  log "WARN" "$message"
}

function log_error {
  local readonly message="$1"
  log "ERROR" "$message"
}

function contains {
    # odd syntax here for passing array parameters: http://stackoverflow.com/questions/8082947/how-to-pass-an-array-to-a-bash-function
    local list=$1[@]
    local elem=$2

    # echo "list" ${!list}
    # echo "elem" $elem

    for i in "${!list}"
    do
        # echo "Checking to see if" "$i" "is the same as" "${elem}"
        if [ "$i" == "${elem}" ] ; then
            # echo "$i" "was the same as" "${elem}"
            return 0
        fi
    done

    # echo "Could not find element"
    return 1
}

## Valid regions for Inspector installation
VALID_REGIONS={"us-east-1"}

log_info "Finding AWS Region to verify Inspector is available"
REGION=`curl http://169.254.169.254/latest/dynamic/instance-identity/document|grep region|awk -F\" '{print $4}'`

if contains VALID_REGIONS $REGION; then
    log_info "Downloading Inspector from AWS"

    wget https://d1wk0tztpsntt1.cloudfront.net/linux/latest/install 
    if [ $? -ne 0 ]; then
        log_error "Error: Could not download Inspector from AWS"
        exit 1 
    fi

    sudo bash install
    if [ $? -ne 0 ]; then
        log_error "Inspector installation failed."
        exit 1
    fi
else
    log_info "Inspector is not availale in your region $REGION.  Will not install."
fi

exit 0