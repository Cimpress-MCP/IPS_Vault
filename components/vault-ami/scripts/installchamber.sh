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

function assert_is_installed {
  local readonly name="$1"

  if [[ ! $(command -v ${name}) ]]; then
    log_error "The binary '$name' is required by this script but is not installed or in the system's PATH."
    exit 1
  fi
}

assert_is_installed "go"

export GOPATH=~/go
mkdir go

log_info "Cloning Chamber from GitHub"
git clone https://github.com/segmentio/chamber.git
if [ $? -ne 0 ]; then
    log_error "Error: Git Clone failed"
    exit 1 
fi
cd chamber
go get
if [ $? -ne 0 ]; then
    log_error "Error: Go failed to download dependencies for Chamber build"
    exit 1 
fi
go build
if [ $? -ne 0 ]; then
    log_error "Error: Go failed to build Chamber"
    exit 1 
fi
sudo mv chamber /usr/bin
exit 0