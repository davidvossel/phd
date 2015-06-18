#!/bin/bash


crm_simulate -x ${1}.xml -D ${1}.dot -G ${1}.exp -SQ -s $* 2> /dev/null > ${1}.scores
crm_simulate -x ${1}.xml -S > ${1}.summary
