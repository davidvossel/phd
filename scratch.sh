#!/bin/bash


#the plan
# unpack yaml in scenario by writing yaml to file and then processing file.
# validate yaml the same way we are now. export requirements from yaml file
# next up add scenario specific options to yaml, process them with a different prefix
# validate scenario specific options based on if they are required or not.

# After all this, build metadata xml out of processed yaml that can be printed to stdout.


# insert test code here
function parse_yaml {
	local prefix=$2
	local s='[[:space:]]*' w='[a-zA-Z0-9_]*' fs=$(echo @|tr @ '\034')
	sed -ne "s|^\($s\):|\1|" \
		-e "s|^\($s\)\($w\)$s:$s[\"']\(.*\)[\"']$s\$|\1$fs\2$fs\3|p" \
		-e "s|^\($s\)\($w\)$s:$s\(.*\)$s\$|\1$fs\2$fs\3|p"  $1 |
	awk -F$fs '{
		indent = length($1)/2;
		vname[indent] = $2;
		for (i in vname) {if (i > indent) {delete vname[i]}}
		if (length($3) > 0) {
			vn=""; for (i=0; i<indent; i++) {vn=(vn)(vname[i])("_")}
			printf("%s%s%s=\"%s\"\n", "'$prefix'",vn, $2, $3);
		}
	}'
}

rm -f testyaml
cat << END >> testyaml

info:
  description: "example scenario"
  long_description: "Example scenario for deploying HA apache"

requirements:
  nodes: 1
  cluster_init: 1
  floating_ips: 1
  packages: "pacemaker corosync pcs httpd wget"
  distro: rhel6 rhel7

options:
  html_text:
    description: "The text to put in the servers index file's body"
    type: string
    required: false
    default: "My test site"
END

parse_yaml "testyaml"  "META_"
