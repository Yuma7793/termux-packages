TERMUX_PKG_HOMEPAGE=https://boinc.berkeley.edu/
TERMUX_PKG_DESCRIPTION="Open-source software for volunteer computing"
TERMUX_PKG_LICENSE="LGPL-3.0"
TERMUX_PKG_MAINTAINER="@termux"
TERMUX_PKG_VERSION=7.22.0
TERMUX_PKG_SRCURL=https://github.com/BOINC/boinc/archive/client_release/${TERMUX_PKG_VERSION:0:4}/${TERMUX_PKG_VERSION}.tar.gz
TERMUX_PKG_SHA256=7c7014300cb6e859b6f784f5c76ff2cb96d36ae35d90e03d1e2e59174cb7c927
TERMUX_PKG_DEPENDS="libandroid-execinfo, libandroid-shmem, libc++, libcurl, openssl, zlib"
TERMUX_PKG_NO_STATICSPLIT=true
TERMUX_PKG_EXTRA_CONFIGURE_ARGS="
--disable-server
--disable-manager
"

# etc/boinc-client.conf is not for Android, extra hooks needed to work
TERMUX_PKG_RM_AFTER_INSTALL="
etc/boinc-client.conf
"

termux_step_pre_configure() {
	# for benchmark purposes
	export CFLAGS="${CFLAGS/-Oz/-Os} -flto -fPIC"
	export CXXFLAGS="${CXXFLAGS/-Oz/-Os} -flto -fPIC"
	export LDFLAGS+=" -landroid-shmem -landroid-execinfo $(${CC} -print-libgcc-file-name)"
	./_autosetup
}

termux_step_post_make_install() {
	install -Dm644 "${TERMUX_PKG_SRCDIR}/client/scripts/boinc.bash" "${TERMUX_PREFIX}/share/bash-completion/completions/boinc"
}
