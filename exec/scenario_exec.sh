#!/bin/bash

if [ -z "$PHDCONST_ROOT" ]; then
	if [ "$(basename $(pwd))" = "exec" ]; then
		PHDCONST_ROOT=$(dirname $(pwd))
	else
		PHDCONST_ROOT=$(pwd)
	fi
fi

. ${PHDCONST_ROOT}/lib/transport_ssh.sh
. ${PHDCONST_ROOT}/lib/utils.sh
. ${PHDCONST_ROOT}/lib/scenario.sh
. ${PHDCONST_ROOT}/lib/definition.sh

definition_unpack $1
scenario_unpack $2

print_definition
print_scenario

scenario_exec
