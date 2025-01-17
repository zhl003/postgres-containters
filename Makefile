ifndef CCPROOT
	export CCPROOT=$(shell pwd)
endif

# Default values if not already set
CCP_BASEOS ?= debian
BASE_IMAGE_OS ?= $(CCP_BASEOS)
CCP_PGVERSION ?= 14
CCP_PG_FULLVERSION ?= 14.2
CCP_PATRONI_VERSION ?= 2.1.3
CCP_BACKREST_VERSION ?= 2.36
CCP_VERSION ?= 2.1.1
CCP_POSTGIS_VERSION ?= 3.1
PACKAGER ?= apt
DOCKERBASEREGISTRY ?= docker.io/
CCP_IMAGE_TAG ?= $(CCP_BASEOS)-$(CCP_PG_FULLVERSION)-$(CCP_VERSION)
CCP_POSTGIS_IMAGE_TAG ?= $(CCP_BASEOS)-$(CCP_PG_FULLVERSION)-$(CCP_POSTGIS_VERSION)-$(CCP_VERSION)
CCP_IMAGE_PREFIX ?= radondb
test:
	@echo $(CCP_POSTGIS_IMAGE_TAG)

# Valid values: buildah (default), docker
IMGBUILDER ?= docker
# Determines whether or not images should be pushed to the local docker daemon when building with
# a tool other than docker (e.g. when building with buildah)
IMG_PUSH_TO_DOCKER_DAEMON ?= true
# The utility to use when pushing/pulling to and from an image repo (e.g. docker or buildah)
IMG_PUSHER_PULLER ?= docker
# Defines the sudo command that should be prepended to various build commands when rootless builds are
# not enabled
IMGCMDSUDO=
ifneq ("$(IMG_ROOTLESS_BUILD)", "true")
	IMGCMDSUDO=sudo --preserve-env
endif
IMGCMDSTEM=$(IMGCMDSUDO) buildah bud --layers $(SQUASH)
DFSET=$(CCP_BASEOS)

# Default the buildah format to docker to ensure it is possible to pull the images from a docker
# repository using docker (otherwise the images may not be recognized)
export BUILDAH_FORMAT ?= docker

# Allows simplification of IMGBUILDER switching
ifeq ("$(IMGBUILDER)","docker")
	IMGCMDSTEM=docker build
endif

# Allows consolidation of debian Dockerfile sets
ifeq ("$(CCP_BASEOS)", "debian")
        DFSET=debian
        PACKAGER=apt
        BASE_IMAGE_OS=bullseye-slim
endif

.PHONY:	all license pgbackrest-images pg-independent-images pgimages

# list of image names, helpful in pushing
images = radondb-postgres \
	radondb-postgres-ha \
	radondb-upgrade \
	radondb-pgbackrest \
	radondb-pgbackrest-repo \
	radondb-pgadmin4 \
	radondb-pgbadger \
	radondb-pgbouncer \
	radondb-pgpool

# Default target
all: pgimages pg-independent-images pgbackrest-images

# Build images that either don't have a PG dependency or using the latest PG version is all that is needed
pg-independent-images:  pgbadger pgbouncer pgpool
# pg-independent-images: pgbadger pgpool

# Build images that require a specific postgres version - ordered for potential concurrent benefits
pgimages: postgres postgres-ha postgres-gis postgres-gis-ha upgrade

# Build images based on pgBackRest
pgbackrest-images: pgbackrest pgbackrest-repo

#===========================================
# Targets generating pg-based images
#===========================================

pgadmin4: pgadmin4-img-$(IMGBUILDER)
pgbackrest: pgbackrest-pgimg-$(IMGBUILDER)
pgbackrest-repo: pgbackrest-repo-pgimg-$(IMGBUILDER)
pgbadger: pgbadger-img-$(IMGBUILDER)
pgbouncer: pgbouncer-img-$(IMGBUILDER)
pgpool: pgpool-img-$(IMGBUILDER)
postgres: postgres-pgimg-$(IMGBUILDER)
postgres-ha: postgres-ha-pgimg-$(IMGBUILDER)
postgres-gis: postgres-gis-pgimg-$(IMGBUILDER)
postgres-gis-ha: postgres-gis-ha-pgimg-$(IMGBUILDER)

#===========================================
# Pattern-based image generation targets
#===========================================

$(CCPROOT)/build/%/Dockerfile:
	$(error No Dockerfile found for $* naming pattern: [$@])

# ----- Base Image -----
ccbase-image: ccbase-image-$(IMGBUILDER) pg-base-image-build
pg-base-image-build: $(CCPROOT)/$(CCP_PGVERSION)/bullseye/Dockerfile
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/$(CCP_PGVERSION)/bullseye/Dockerfile \
		-t $(CCP_IMAGE_PREFIX)/radondb-pg-base:$(CCP_IMAGE_TAG) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg BASEOS=$(CCP_BASEOS) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		$(CCPROOT)
ccbase-image-build: $(CCPROOT)/build/base/Dockerfile
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/build/base/Dockerfile \
		-t $(CCP_IMAGE_PREFIX)/radondb-base:$(CCP_IMAGE_TAG) \
		--build-arg BASEOS=$(CCP_BASEOS) \
		--build-arg RELVER=$(CCP_VERSION) \
		--build-arg DFSET=$(DFSET) \
		--build-arg PACKAGER=$(PACKAGER) \
		--build-arg DOCKERBASEREGISTRY=$(DOCKERBASEREGISTRY) \
		--build-arg BASE_IMAGE_OS=$(BASE_IMAGE_OS) \
		--build-arg PG_LBL=${subst .,,$(CCP_PGVERSION)} \
		$(CCPROOT)

ccbase-image-buildah: ccbase-image-build ;
# only push to docker daemon if variable IMG_PUSH_TO_DOCKER_DAEMON is set to "true"
ifeq ("$(IMG_PUSH_TO_DOCKER_DAEMON)", "true")
	sudo --preserve-env docker push $(CCP_IMAGE_PREFIX)/radondb-base:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/radondb-base:$(CCP_IMAGE_TAG)
endif

ccbase-image-docker: ccbase-image-build

# ----- Base Image Ext -----
ccbase-ext-image-build: ccbase-image $(CCPROOT)/build/base-ext/Dockerfile
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/build/base-ext/Dockerfile \
		-t $(CCP_IMAGE_PREFIX)/radondb-base-ext:$(CCP_IMAGE_TAG) \
		--build-arg BASEOS=$(CCP_BASEOS) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PACKAGER=$(PACKAGER) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		$(CCPROOT)

ccbase-ext-image-buildah: ccbase-ext-image-build ;
# only push to docker daemon if variable IMG_PUSH_TO_DOCKER_DAEMON is set to "true"
ifeq ("$(IMG_PUSH_TO_DOCKER_DAEMON)", "true")
	sudo --preserve-env docker push $(CCP_IMAGE_PREFIX)/radondb-base-ext:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/radondb-base-ext:$(CCP_IMAGE_TAG)
endif

ccbase-ext-image-docker: ccbase-ext-image-build

# ----- Special case pg-based image (postgres) -----
# Special case args: BACKREST_VER
postgres-pgimg-build: ccbase-image $(CCPROOT)/build/postgres/Dockerfile
	$(IMGCMDSTEM)  \
		-f $(CCPROOT)/build/postgres/Dockerfile \
		-t $(CCP_IMAGE_PREFIX)/radondb-postgres:$(CCP_IMAGE_TAG) \
		--build-arg BASEOS=$(CCP_BASEOS) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_LBL=${subst .,,$(CCP_PGVERSION)} \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg BACKREST_VER=$(CCP_BACKREST_VERSION) \
		--build-arg DFSET=$(DFSET) \
		--build-arg PACKAGER=$(PACKAGER) \
		--build-arg BASE_IMAGE_NAME=radondb-base \
		--build-arg PATRONI_VER=$(CCP_PATRONI_VERSION) \
		$(CCPROOT)

postgres-pgimg-buildah: postgres-pgimg-build ;
# only push to docker daemon if variable IMG_PUSH_TO_DOCKER_DAEMON is set to "true"
ifeq ("$(IMG_PUSH_TO_DOCKER_DAEMON)", "true")
	sudo --preserve-env docker push $(CCP_IMAGE_PREFIX)/radondb-postgres:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/radondb-postgres:$(CCP_IMAGE_TAG)
endif

postgres-pgimg-docker: postgres-pgimg-build

# ----- Special case pg-based image (postgres-gis-base) -----
# Used as the base for the postgres-gis image.
postgres-gis-base-pgimg-build: ccbase-ext-image-build $(CCPROOT)/build/postgres/Dockerfile
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/build/postgres/Dockerfile \
		-t $(CCP_IMAGE_PREFIX)/radondb-postgres-gis-base:$(CCP_IMAGE_TAG) \
		--build-arg BASEOS=$(CCP_BASEOS) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_LBL=${subst .,,$(CCP_PGVERSION)} \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg BACKREST_VER=$(CCP_BACKREST_VERSION) \
		--build-arg DFSET=$(DFSET) \
		--build-arg PACKAGER=$(PACKAGER) \
		--build-arg PATRONI_VER=$(CCP_PATRONI_VERSION) \
		--build-arg BASE_IMAGE_NAME=radondb-base-ext \
		$(CCPROOT)

postgres-gis-base-pgimg-buildah: postgres-gis-base-pgimg-build ;
# only push to docker daemon if variable IMG_PUSH_TO_DOCKER_DAEMON is set to "true"
ifeq ("$(IMG_PUSH_TO_DOCKER_DAEMON)", "true")
	sudo --preserve-env docker push $(CCP_IMAGE_PREFIX)/radondb-postgres-gis-base:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/radondb-postgres-gis-base:$(CCP_IMAGE_TAG)
endif

# ----- Special case pg-based image (postgres-gis) -----
# Special case args: POSTGIS_LBL
postgres-gis-pgimg-build: $(CCPROOT)/build/postgres-gis/Dockerfile
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/build/postgres-gis/Dockerfile \
		-t $(CCP_IMAGE_PREFIX)/radondb-postgres-gis:$(CCP_POSTGIS_IMAGE_TAG) \
		--build-arg BASEOS=$(CCP_BASEOS) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg POSTGIS_LBL=$(subst .,,$(CCP_POSTGIS_VERSION)) \
		--build-arg DFSET=$(DFSET) \
		--build-arg PACKAGER=$(PACKAGER) \
		$(CCPROOT)

postgres-gis-pgimg-buildah: postgres-gis-pgimg-build ;
# only push to docker daemon if variable IMG_PUSH_TO_DOCKER_DAEMON is set to "true"
ifeq ("$(IMG_PUSH_TO_DOCKER_DAEMON)", "true")
	sudo --preserve-env docker push $(CCP_IMAGE_PREFIX)/radondb-postgres-gis:$(CCP_POSTGIS_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/radondb-postgres-gis:$(CCP_POSTGIS_IMAGE_TAG)
endif

postgres-gis-pgimg-docker: postgres-gis-pgimg-build

# ----- Special case image (pgbackrest) -----

# build the needed binary
build-pgbackrest:
	go build -o bin/pgbackrest/pgbackrest ./cmd/pgbackrest

# Special case args: BACKREST_VER
pgbackrest-pgimg-build:  build-pgbackrest $(CCPROOT)/build/pgbackrest/Dockerfile
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/build/pgbackrest/Dockerfile \
		-t $(CCP_IMAGE_PREFIX)/radondb-pgbackrest:$(CCP_IMAGE_TAG) \
		--build-arg BASEOS=$(CCP_BASEOS) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg BASE_IMAGE_OS=$(BASE_IMAGE_OS) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg BACKREST_VER=$(CCP_BACKREST_VERSION) \
		--build-arg PACKAGER=$(PACKAGER) \
		$(CCPROOT)

pgbackrest-pgimg-buildah: pgbackrest-pgimg-build ;
# only push to docker daemon if variable IMG_PUSH_TO_DOCKER_DAEMON is set to "true"
ifeq ("$(IMG_PUSH_TO_DOCKER_DAEMON)", "true")
	sudo --preserve-env docker push $(CCP_IMAGE_PREFIX)/radondb-pgbackrest:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/radondb-pgbackrest:$(CCP_IMAGE_TAG)
endif

pgbackrest-pgimg-docker: pgbackrest-pgimg-build

# ----- Special case image (upgrade) -----

# Special case args: UPGRADE_PG_VERSIONS (defines all versions of PG that will be installed)
upgrade-img-build: ccbase-image $(CCPROOT)/build/upgrade/Dockerfile
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/build/upgrade/Dockerfile \
		-t $(CCP_IMAGE_PREFIX)/radondb-upgrade:$(CCP_IMAGE_TAG) \
		--build-arg BASEOS=$(CCP_BASEOS) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg DFSET=$(DFSET) \
		--build-arg PACKAGER=$(PACKAGER) \
		--build-arg UPGRADE_PG_VERSIONS="$(shell ls|grep "^[0-9][0-9]$")" \
		$(CCPROOT)

upgrade-img-buildah: upgrade-img-build ;
# only push to docker daemon if variable IMG_PUSH_TO_DOCKER_DAEMON is set to "true"
ifeq ("$(IMG_PUSH_TO_DOCKER_DAEMON)", "true")
	sudo --preserve-env docker push $(CCP_IMAGE_PREFIX)/radondb-upgrade:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/radondb-upgrade:$(CCP_IMAGE_TAG)
endif

upgrade-img-docker: upgrade-img-build

# ----- Extra images -----
%-img-build:  $(CCPROOT)/build/%/Dockerfile
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/build/$*/Dockerfile \
		-t $(CCP_IMAGE_PREFIX)/radondb-$*:$(CCP_IMAGE_TAG) \
		--build-arg BASEOS=$(CCP_BASEOS) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg DFSET=$(DFSET) \
		--build-arg BASE_IMAGE_OS=$(BASE_IMAGE_OS) \
		--build-arg PACKAGER=$(PACKAGER) \
		$(CCPROOT)

%-img-buildah: %-img-build ;
# only push to docker daemon if variable IMG_PUSH_TO_DOCKER_DAEMON is set to "true"
ifeq ("$(IMG_PUSH_TO_DOCKER_DAEMON)", "true")
	sudo --preserve-env docker push $(CCP_IMAGE_PREFIX)/radondb-$*:$(CCP_IMAGE_TAG) docker-daemon:$(CCP_IMAGE_PREFIX)/radondb-$*:$(CCP_IMAGE_TAG)
endif

%-img-docker: %-img-build ;

# ----- Upgrade Images -----
upgrade: upgrade-$(CCP_PGVERSION)

upgrade-%: upgrade-img-$(IMGBUILDER) ;

upgrade-9.5: # Do nothing but log to avoid erroring out on missing Dockerfile
	$(info Upgrade build skipped for 9.5)

#=================
# Utility targets
#=================
setup:
	$(CCPROOT)/bin/install-deps.sh

docbuild:
	cd $(CCPROOT) && ./generate-docs.sh

license:
	./bin/license_aggregator.sh

push: push-gis $(images:%=push-%) ;

push-gis:
	$(IMG_PUSHER_PULLER) push $(CCP_IMAGE_PREFIX)/radondb-postgres-gis:$(CCP_POSTGIS_IMAGE_TAG)

push-%:
	$(IMG_PUSHER_PULLER) push $(CCP_IMAGE_PREFIX)/$*:$(CCP_IMAGE_TAG)

-include Makefile.build
postgres-ha-pgimg-docker: postgres-ha-pgimg-build
postgres-ha-pgimg-build: postgres-pgimg-build $(CCPROOT)/build/postgres-ha/Dockerfile
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/build/postgres-ha/Dockerfile \
		-t $(CCP_IMAGE_PREFIX)/radondb-postgres-ha:$(CCP_IMAGE_TAG) \
		--build-arg BASEOS=$(CCP_BASEOS) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg PATRONI_VER=$(CCP_PATRONI_VERSION) \
		--build-arg DFSET=$(DFSET) \
		--build-arg PACKAGER=$(PACKAGER) \
		$(CCPROOT)
postgres-gis-ha-pgimg-docker: postgres-gis-ha-pgimg-build
postgres-gis-ha-pgimg-build: postgres-gis-pgimg-build $(CCPROOT)/build/postgres-gis-ha/Dockerfile
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/build/postgres-gis-ha/Dockerfile \
		-t $(CCP_IMAGE_PREFIX)/radondb-postgres-gis-ha:$(CCP_POSTGIS_IMAGE_TAG) \
		--build-arg BASEOS=$(CCP_BASEOS) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PG_MAJOR=$(CCP_PGVERSION) \
		--build-arg PATRONI_VER=$(CCP_PATRONI_VERSION) \
		--build-arg POSTGIS_VER=$(CCP_POSTGIS_VERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		--build-arg DFSET=$(DFSET) \
		--build-arg PACKAGER=$(PACKAGER) \
		$(CCPROOT)
pgbackrest-repo-pgimg-docker: pgbackrest-repo-pgimg-build
pgbackrest-repo-pgimg-build: ccbase-image build-pgbackrest pgbackrest $(CCPROOT)/build/pgbackrest-repo/Dockerfile
	$(IMGCMDSTEM) \
		-f $(CCPROOT)/build/pgbackrest-repo/Dockerfile \
		-t $(CCP_IMAGE_PREFIX)/radondb-pgbackrest-repo:$(CCP_IMAGE_TAG) \
		--build-arg BASEOS=$(CCP_BASEOS) \
		--build-arg BASEVER=$(CCP_VERSION) \
		--build-arg PG_FULL=$(CCP_PG_FULLVERSION) \
		--build-arg PREFIX=$(CCP_IMAGE_PREFIX) \
		$(CCPROOT)
