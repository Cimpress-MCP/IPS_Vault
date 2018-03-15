#!/bin/sh

export GOPATH=~/go
mkdir go

git clone https://github.com/segmentio/chamber.git
cd chamber
go get
go build
sudo mv chamber /usr/bin