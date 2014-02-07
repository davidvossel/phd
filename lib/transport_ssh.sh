#!/bin/bash

# Copyright (c) 2013 David Vossel <dvossel@redhat.com>
#                    All Rights Reserved.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of version 2 of the GNU General Public License as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it would be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
#
# Further, this software is distributed without any warranty that it is
# free of the rightful claim of any third person regarding infringement
# or the like.  Any license provided herein, whether implied or
# otherwise, applies only to this software file.  Patent licenses, if
# any, provided herein do not apply to combinations of this program with
# other software, or any other product whatsoever.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write the Free Software Foundation,
# Inc., 59 Temple Place - Suite 330, Boston MA 02111-1307, USA.
#

#. ${PHDCONST_ROOT}/lib/phd_utils_api.sh
PHD_SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=30 -o BatchMode=yes"

phd_ssh_cp()
{
	local src=$1
	local dest=$2
	local node=$3
	local fullcmd="scp $PHD_SSH_OPTS $src root@$node:${dest}"

	timeout -s kill 120 $fullcmd
}

phd_ssh_cmd_exec()
{
	local cmd=$1
	local node=$2
	local fullcmd="ssh $PHD_SSH_OPTS -l root $node $cmd"

	timeout -s KILL 120 $fullcmd
}

#phd_ssh_connection_verify()
#{
	#TODO
#	return 0
#}
