
-include Makefile

PACKAGE		?= phd

# Force 'make dist' to be consistent with 'make export'
distprefix		= $(PACKAGE)
distdir			= $(distprefix)-$(TAG)
TARFILE			= $(distdir).tar.gz
DIST_ARCHIVES		= $(TARFILE)

RPM_ROOT	= $(shell pwd)
RPM_OPTS	= --define "_sourcedir $(RPM_ROOT)" 	\
		  --define "_specdir   $(RPM_ROOT)" 	\
		  --define "_srcrpmdir $(RPM_ROOT)" 	\

MOCK_OPTIONS	?= --resultdir=$(RPM_ROOT)/mock --no-cleanup-after

# Default to fedora compliant spec files
# SLES:     /etc/SuSE-release
# openSUSE: /etc/SuSE-release
# RHEL:     /etc/redhat-release
# Fedora:   /etc/fedora-release, /etc/redhat-release, /etc/system-release
F       ?= $(shell test ! -e /etc/fedora-release && echo 0; test -e /etc/fedora-release && rpm --eval %{fedora})
ARCH    ?= $(shell test -e /etc/fedora-release && rpm --eval %{_arch})
MOCK_CFG ?= $(shell test -e /etc/fedora-release && echo fedora-$(F)-$(ARCH))
DISTRO  ?= $(shell test -e /etc/SuSE-release && echo suse; echo fedora)
TAG     ?= $(shell git log --pretty="format:%h" -n 1)
#WITH    ?= --without doc

LAST_RC		?= $(shell test -e /Volumes || git tag -l | grep phd | sort -Vr | grep rc | head -n 1)
LAST_RELEASE	?= $(shell test -e /Volumes || git tag -l | grep phd | sort -Vr | grep -v rc | head -n 1)
NEXT_RELEASE	?= $(shell echo $(LAST_RELEASE) | awk -F. '/[0-9]+\./{$$3+=1;OFS=".";print $$1,$$2,$$3}')

beekhof:
	echo $(LAST_RELEASE) $(NEXT_RELEASE)

#LAST_COUNT      = $(shell test ! -e $(BUILD_COUNTER) && echo 0; test -e $(BUILD_COUNTER) && cat $(BUILD_COUNTER))
LAST_COUNT		= $(shell git log --pretty=format:%s $(LAST_RELEASE)..HEAD | wc -l)
COUNT           = $(shell expr 1 + $(LAST_COUNT))

init:
	./autogen.sh

export:
	rm -f $(PACKAGE)-dirty.tar.* $(PACKAGE)-tip.tar.* $(PACKAGE)-HEAD.tar.*
	if [ ! -f $(TARFILE) ]; then						\
	    rm -f $(PACKAGE).tar.*;						\
	    if [ $(TAG) = dirty ]; then 					\
		git commit -m "DO-NOT-PUSH" -a;					\
		git archive --prefix=$(distdir)/ HEAD | gzip > $(TARFILE);	\
		git reset --mixed HEAD^; 					\
	    else								\
		git archive --prefix=$(distdir)/ $(TAG) | gzip > $(TARFILE);	\
	    fi;									\
	    echo `date`: Rebuilt $(TARFILE);					\
	else									\
	    echo `date`: Using existing tarball: $(TARFILE);			\
	fi

# Works for all fedora based distros
$(PACKAGE)-%.spec: $(PACKAGE).spec.in
	rm -f $@
	if [ x != x"`git ls-files -m | grep phd.spec.in`" ]; then		\
	    cp $(PACKAGE).spec.in $(PACKAGE)-$*.spec;				\
	    echo "Rebuilt $@ (local modifications)";				\
	elif [ x = x"`git show $(TAG):phd.spec.in 2>/dev/null`" ]; then	\
	    cp $(PACKAGE).spec.in $(PACKAGE)-$*.spec;				\
	    echo "Rebuilt $@";							\
	else 									\
	    git show $(TAG):$(PACKAGE).spec.in >> $(PACKAGE)-$*.spec;		\
	    echo "Rebuilt $@ from $(TAG)";					\
	fi

srpm-%:	export $(PACKAGE)-%.spec
	rm -f *.src.rpm
	cp $(PACKAGE)-$*.spec $(PACKAGE).spec
	sed -i 's/Source0:.*/Source0:\ $(TARFILE)/' $(PACKAGE).spec
	sed -i 's/global\ specversion.*/global\ specversion\ $(COUNT)/' $(PACKAGE).spec
	sed -i 's/global\ upstream_version.*/global\ upstream_version\ $(TAG)/' $(PACKAGE).spec
	sed -i 's/global\ upstream_prefix.*/global\ upstream_prefix\ $(distprefix)/' $(PACKAGE).spec
	case $(TAG) in 								\
		phd*) sed -i 's/Version:.*/Version:\ $(shell echo $(TAG) | sed -e s:phd-:: -e s:-.*::)/' $(PACKAGE).spec;;		\
		*)          sed -i 's/Version:.*/Version:\ $(shell echo $(NEXT_RELEASE) | sed -e s:phd-:: -e s:-.*::)/' $(PACKAGE).spec;; 	\
	esac
	rpmbuild -bs --define "dist .$*" $(RPM_OPTS) $(WITH)  $(PACKAGE).spec

chroot: mock-$(MOCK_CFG) mock-install-$(MOCK_CFG) mock-sh-$(MOCK_CFG)
	echo "Done"

mock-next:
	make F=$(shell expr 1 + $(F)) mock

mock-rawhide:
	make F=rawhide mock

mock-install-%:
	echo "Installing packages"
	mock --root=$* $(MOCK_OPTIONS) --install $(RPM_ROOT)/mock/*.rpm vi sudo valgrind lcov gdb fence-agents

mock-sh: mock-sh-$(MOCK_CFG)
	echo "Done"

mock-sh-%:
	echo "Connecting"
	mock --root=$* $(MOCK_OPTIONS) --shell
	echo "Done"

# eg. WITH="--with cman" make rpm
mock-%:
	make srpm-$(firstword $(shell echo $(@:mock-%=%) | tr '-' ' '))
	-rm -rf $(RPM_ROOT)/mock
	@echo "mock --root=$* --rebuild $(WITH) $(MOCK_OPTIONS) $(RPM_ROOT)/*.src.rpm"
	mock --root=$* --no-cleanup-after --rebuild $(WITH) $(MOCK_OPTIONS) $(RPM_ROOT)/*.src.rpm

srpm:	srpm-$(DISTRO)
	echo "Done"

mock:   mock-$(MOCK_CFG)
	echo "Done"

rpm-dep: $(PACKAGE)-$(DISTRO).spec
	if [ x != x`which yum-builddep 2>/dev/null` ]; then			\
	    echo "Installing with yum-builddep";		\
	    sudo yum-builddep $(PACKAGE)-$(DISTRO).spec;	\
	elif [ x != x`which yum 2>/dev/null` ]; then				\
	    echo -e "Installing: $(shell grep BuildRequires phd.spec.in | sed -e s/BuildRequires:// -e s:\>.*0:: | tr '\n' ' ')\n\n";	\
	    sudo yum install $(shell grep BuildRequires phd.spec.in | sed -e s/BuildRequires:// -e s:\>.*0:: | tr '\n' ' ');	\
	elif [ x != x`which zypper` ]; then			\
	    echo -e "Installing: $(shell grep BuildRequires phd.spec.in | sed -e s/BuildRequires:// -e s:\>.*0:: | tr '\n' ' ')\n\n";	\
	    sudo zypper install $(shell grep BuildRequires phd.spec.in | sed -e s/BuildRequires:// -e s:\>.*0:: | tr '\n' ' ');\
	else							\
	    echo "I don't know how to install $(shell grep BuildRequires phd.spec.in | sed -e s/BuildRequires:// -e s:\>.*0:: | tr '\n' ' ')";\
	fi

rpm:	srpm
	@echo To create custom builds, edit the flags and options in $(PACKAGE).spec first
	rpmbuild $(RPM_OPTS) $(WITH) --rebuild $(RPM_ROOT)/*.src.rpm

release:
	make TAG=$(LAST_RELEASE) rpm

rc:
	make TAG=$(LAST_RC) rpm

dirty:
	make TAG=dirty mock


global: clean-generic
	gtags -q

%.8.html: %.8
	echo groff -mandoc `man -w ./$<` -T html > $@
	groff -mandoc `man -w ./$<` -T html > $@
	rsync -azxlSD --progress $@ root@www.clusterlabs.org:/var/www/html/man/

%.7.html: %.7
	echo groff -mandoc `man -w ./$<` -T html > $@
	groff -mandoc `man -w ./$<` -T html > $@
	rsync -azxlSD --progress $@ root@www.clusterlabs.org:/var/www/html/man/

summary:
	@printf "\n* `date +"%a %b %d %Y"` `git config user.name` <`git config user.email`> $(NEXT_RELEASE)-1"
	@printf "\n- Update source tarball to revision: `git id`"
	@printf "\n- Changesets: `git log --pretty=format:'%h' $(LAST_RELEASE)..HEAD | wc -l`"
	@printf "\n- Diff:      "
	@git diff -r $(LAST_RELEASE)..HEAD --stat include lib mcp pengine/*.c pengine/*.h  cib crmd fencing lrmd tools xml | tail -n 1

rc-changes:
	@make NEXT_RELEASE=$(shell echo $(LAST_RC) | sed s:-rc.*::) LAST_RELEASE=$(LAST_RC) changes

changes: summary
	@printf "\n- Features added since $(LAST_RELEASE)\n"
	@git log --pretty=format:'  +%s' --abbrev-commit $(LAST_RELEASE)..HEAD | grep -e Feature: | sed -e 's@Feature:@@' | sort -uf
	@printf "\n- Changes since $(LAST_RELEASE)\n"
	@git log --pretty=format:'  +%s' --abbrev-commit $(LAST_RELEASE)..HEAD | grep -e High: -e Fix: -e Bug | sed -e 's@Fix:@@' -e s@High:@@ -e s@Fencing:@fencing:@ -e 's@Bug@ Bug@' -e s@PE:@pengine:@ | sort -uf

changelog:
	@make changes > ChangeLog
	@printf "\n">> ChangeLog
	git show $(LAST_RELEASE):ChangeLog >> ChangeLog
	@echo -e "\033[1;35m -- Don't forget to run the bumplibs.sh script! --\033[0m"

indent:
	find . -name "*.h" -exec ./p-indent \{\} \;
	find . -name "*.c" -exec ./p-indent \{\} \;
	git co HEAD crmd/fsa_proto.h lib/gnu

rel-tags: tags
	find . -name TAGS -exec sed -i 's:\(.*\)/\(.*\)/TAGS:\2/TAGS:g' \{\} \;


# V3	= scandir unsetenv alphasort
# V2	= setenv strerror strchrnul strndup
# http://www.gnu.org/software/gnulib/manual/html_node/Initial-import.html#Initial-import
GNU_MODS	= crypto/md5
gnulib-update:
	-test ! -e gnulib && git clone git://git.savannah.gnu.org/gnulib.git
	cd gnulib && git pull
	gnulib/gnulib-tool --source-base=lib/gnu --lgpl=2 --no-vc-files --import $(GNU_MODS)
