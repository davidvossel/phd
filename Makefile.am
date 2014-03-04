
SPEC			= $(PACKAGE_NAME).spec
TARFILE			= $(PACKAGE_NAME)-$(VERSION).tar.gz


EXTRA_DIST		= autogen.sh $(SPEC).in

AUTOMAKE_OPTIONS	= foreign

CLEANFILES	= phd_exec

MAINTAINERCLEANFILES	= Makefile.in aclocal.m4 configure depcomp \
			  config.guess config.sub missing install-sh \
			  autoheader automake autoconf libtool libtoolize \
			  ltmain.sh

SUBDIRS	= lib tests scenarios environment doc

ACLOCAL_AMFLAGS		= -I m4

sbin_SCRIPTS = phd_exec
