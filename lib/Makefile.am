
SPEC			= $(PACKAGE_NAME).spec
TARFILE			= $(PACKAGE_NAME)-$(VERSION).tar.gz

AUTOMAKE_OPTIONS	= foreign

MAINTAINERCLEANFILES	= Makefile.in aclocal.m4 configure depcomp \
			  config.guess config.sub missing install-sh \
			  autoheader automake autoconf libtool libtoolize \
			  ltmain.sh

ACLOCAL_AMFLAGS		= -I m4

phd_libdir = $(libexecdir)/$(PACKAGE_NAME)/lib

phd_lib_SCRIPTS = definition.sh	\
	pacemaker.sh	\
	phd_rsc_api.sh	\
	phd_utils_api.sh	\
	scenario_engine.sh	\
	shared_storage.sh	\
	transport_ssh.sh

