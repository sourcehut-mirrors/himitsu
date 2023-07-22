#!/bin/sh
export XDG_DATA_HOME=$PWD/.teststore
export XDG_CONFIG_HOME=$PWD/.teststore
export XDG_RUNTIME_DIR=$XDG_DATA_HOME/runtime
mkdir -p $XDG_RUNTIME_DIR
chmod 700 $XDG_RUNTIME_DIR
