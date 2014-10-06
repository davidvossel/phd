
SPEC			= $(PACKAGE_NAME).spec
TARFILE			= $(PACKAGE_NAME)-$(VERSION).tar.gz


EXTRA_DIST		= autogen.sh $(SPEC).in

AUTOMAKE_OPTIONS	= foreign

MAINTAINERCLEANFILES	= Makefile.in aclocal.m4 configure depcomp \
			  config.guess config.sub missing install-sh \
			  autoheader automake autoconf libtool libtoolize \
			  ltmain.sh

SUBDIRS	= lib tests scenarios environment doc tools

ACLOCAL_AMFLAGS		= -I m4
