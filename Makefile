SHELL := bash -O extglob
TRUNK?=$(PWD)

STRIP?=${CROSS_TC}-strip
CFLAGS=$(RICE_CFLAGS)
CFLAGS+=-Wno-deprecated
ifeq ($(DEBUG),1)
	CFLAGS += -DDEBUG_TRACE
	ENABLE_DB_LOGGING=1
endif

ifeq ($(ENABLE_DB_LOGGING),1)
	CFLAGS += -DENABLE_DB_LOGGING
endif

ifeq ($(FAKE_ROOT),1)
	CFLAGS += -DFAKE_ROOT
endif

ifdef ALT_SHELL
	CFLAGS += -DALT_SHELL=\\\"$(ALT_SHELL)\\\"
endif

COMBINED_BUILD=1
ifeq ($(REVERSE_CONNECT),1)
	COMBINED_BUILD=0
	CLI_CFLAGS += -DCLI_REVERSE_CONNECT
	SVR_CFLAGS += -DSVR_REVERSE_CONNECT
endif

ifeq ($(BUILDSTATIC),1)
	LDFLAGS+="-static"
endif

CLI_CFLAGS += $(CFLAGS)
SVR_CFLAGS += $(CFLAGS)

CONFIG_DROPBEAR_STAMP=.config_dropbear_stamp
PATCH_DROPBEAR_STAMP=.patch_dropbear_stamp
CONFIG_SFTP_STAMP=.config_sftp_stamp
CONFIG_XZDEC_STAMP=.config_xz_stamp
CONFIG_OPTIONS=--disable-syslog --disable-pam --disable-shadow
OPENSSH_CONFIG_OPTIONS=--without-openssl

$(PATCH_DROPBEAR_STAMP):
	cd dropbear/src && patch -p1 -l < ../../dropbear_be_cool.patch
	touch $@

$(CONFIG_DROPBEAR_STAMP): $(PATCH_DROPBEAR_STAMP)
	cd dropbear && \
	./configure --verbose LDFLAGS="$(LDFLAGS)" $(CONFIG_OPTIONS) --host=$(CROSS_TC) CFLAGS="$(SVR_CFLAGS)"
	touch $@

$(CONFIG_SFTP_STAMP):
	cd openssh && autoreconf && \
	./configure --verbose LDFLAGS="$(LDFLAGS)" $(OPENSSH_CONFIG_OPTIONS) --host=$(CROSS_TC)
	sed -i 's/-fzero-call-used-regs=used//g' openssh/Makefile
	sed -i 's/-fzero-call-used-regs=used//g' openssh/openbsd-compat/Makefile
	touch $@

$(CONFIG_XZDEC_STAMP):
	cd xz && autoreconf && \
	./configure --host ${CROSS_TC} --enable-static --disable-debug --disable-dependency-tracking --disable-silent-rules --disable-shared --disable-nls --disable-xz --disable-lzmadec --disable-lzmainfo --disable-microlzma
	touch $@


multi: $(CONFIG_DROPBEAR_STAMP) sftp-server xzdec
	mkdir -p build
	make $(JOBSFLAGS) -C dropbear PROGRAMS="dropbear dbclient scp" MULTI=1 
	$(STRIP) dropbear/dropbearmulti
	cp dropbear/dropbearmulti ./build

	
sftp-server: $(CONFIG_SFTP_STAMP)
	mkdir -p build
	make $(JOBSFLAGS) -C openssh sftp-server
	$(STRIP) openssh/sftp-server
	cp openssh/sftp-server ./build

xzdec: $(CONFIG_XZDEC_STAMP)
	mkdir -p build
	make $(JOBSFLAGS) -C xz
	$(STRIP) xz/src/xzdec/xzdec
	cp xz/src/xzdec/xzdec ./build

clean:
	-rm -rf $(PATCH_DROPBEAR_STAMP) $(CONFIG_DROPBEAR_STAMP) $(CONFIG_SFTP_STAMP) $(CONFIG_XZDEC_STAMP) build
	make -C dropbear distclean || true
	cd dropbear && git reset --hard || true
	make -C openssh clean || true
	make -C xz clean || true

