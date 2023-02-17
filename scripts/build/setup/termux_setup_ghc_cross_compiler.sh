# shellcheck shell=bash
__termux_haskell_register_packages() {
	# Register dependency haskell packages with termux-ghc-pkg.
	echo "Registering haskell packages with ghc-pkg...(if any)"
	while read DEP DEP_DIR; do
		if [[ -z $DEP ]]; then
			continue
		elif [[ "${DEP}" == "ERROR" ]]; then
			termux_error_exit "Failed to find dependencies of ${TERMUX_PKG_NAME} [Context: ${FUNCNAME[0]}]"
		fi
		if [[ "${DEP/haskell-/}" != "${DEP}" ]]; then
			sed "s|${TERMUX_PREFIX}/bin/ghc-pkg|$(command -v termux-ghc-pkg)|g" \
				"${TERMUX_PREFIX}/share/haskell/register/${DEP}.sh" | sh
			termux-ghc-pkg recache
			# NOTE: Above command rewrites a cache file at
			# "${TERMUX_PREFIX}/lib/ghc-${TERMUX_GHC_VERSION}/package.conf.d". Since it is done after
			# timestamp creation, we need to remove it in massage step.
		fi
	done <<<"$(
		# shellcheck disable=SC2086
		cd "${TERMUX_SCRIPTDIR}" &&
			./scripts/buildorder.py -i "${TERMUX_PKG_BUILDER_DIR}" ${TERMUX_PACKAGES_DIRECTORIES} || echo "ERROR"
	)"
}

__termux_haskell_setup_build_script() {
	local runtime_folder="$1"

	if ! command -v termux-ghc-setup &>/dev/null; then
		if [ "${TERMUX_ON_DEVICE_BUILD}" = false ]; then
			local build_type=""
			if ! cat "${TERMUX_PKG_SRCDIR}"/*.cabal | grep -wq "^[bB]uild-type:" ||
				cat "${TERMUX_PKG_SRCDIR}"/*.cabal | grep -wq '^[bB]uild-type:\s*[Ss]imple$'; then
				build_type="simple"
			elif cat "${TERMUX_PKG_SRCDIR}"/*.cabal | grep -wq '^[bB]uild-type:\s*[Cc]onfigure$'; then
				build_type="configure"
			elif cat "${TERMUX_PKG_SRCDIR}"/*.cabal | grep -wq '^[bB]uild-type:\s*[Mm]ake$'; then
				build_type="make"
			else
				# Now, it must be a custom build.
				# Compile custom Setup script with GHC and make it available in PATH.
				termux_setup_ghc
				ghc --make "${TERMUX_PKG_SRCDIR}/Setup" -o "${runtime_folder}/bin/termux-ghc-setup"
				return
			fi

			ln -sf "$runtime_folder/bin/${build_type}_setup" \
				"$runtime_folder/bin/termux-ghc-setup"
		else
			# On device, we always have ghc installed. So, always compile Setup script.
			ghc --make "${TERMUX_PKG_SRCDIR}/Setup" -o "${runtime_folder}/bin/termux-ghc-setup"
		fi
	fi
}

# Utility function to setup a GHC cross-compiler toolchain targeting Android.
termux_setup_ghc_cross_compiler() {
	local TERMUX_GHC_VERSION=9.2.5
	local GHC_PREFIX="ghc-cross-${TERMUX_GHC_VERSION}-${TERMUX_ARCH}"
	if [[ "${TERMUX_ON_DEVICE_BUILD}" == "false" ]]; then
		local TERMUX_GHC_RUNTIME_FOLDER

		if [[ "${TERMUX_PACKAGES_OFFLINE-false}" == "true" ]]; then
			TERMUX_GHC_RUNTIME_FOLDER="${TERMUX_SCRIPTDIR}/build-tools/${GHC_PREFIX}-runtime"
		else
			TERMUX_GHC_RUNTIME_FOLDER="${TERMUX_COMMON_CACHEDIR}/${GHC_PREFIX}-runtime"
		fi

		local TERMUX_GHC_TAR="${TERMUX_COMMON_CACHEDIR}/${GHC_PREFIX}.tar.xz"

		export PATH="${TERMUX_GHC_RUNTIME_FOLDER}/bin:${PATH}"

		test -d "${TERMUX_PREFIX}/lib/ghc-${TERMUX_GHC_VERSION}" ||
			termux_error_exit "Package 'ghc-libs' is not installed. It is required by GHC cross-compiler." \
				"You should specify it in 'TERMUX_PKG_BUILD_DEPENDS'."

		if [[ -d "${TERMUX_GHC_RUNTIME_FOLDER}" ]]; then
			__termux_haskell_setup_build_script "${TERMUX_GHC_RUNTIME_FOLDER}"
			__termux_haskell_register_packages
			return
		fi

		local CHECKSUMS
		CHECKSUMS="$(
			cat <<-EOF
				aarch64:47893a77abd35ce5f884bf9c67f8f0437dbcb297d5939e17a3ce7aa74c7d34b8
				arm:dca3aa7a523054e5b472793afb0d750162052ffa762122c1200e5d832187bb86
				i686:428c26a4c2a26737a9c031dbe7545c6514d9042cb28d926ffa8702c2930326c5
				x86_64:1b27fa3dfa02cc9959b43a82b2881b55a1def397da7e7f7ff64406c666763f50
			EOF
		)"

		termux_download "https://github.com/MrAdityaAlok/ghc-cross-tools/releases/download/ghc-v${TERMUX_GHC_VERSION}/ghc-cross-bin-${TERMUX_GHC_VERSION}-${TERMUX_ARCH}.tar.xz" \
			"${TERMUX_GHC_TAR}" \
			"$(echo "${CHECKSUMS}" | grep -w "${TERMUX_ARCH}" | cut -d ':' -f 2)"

		mkdir -p "${TERMUX_GHC_RUNTIME_FOLDER}"

		tar -xf "${TERMUX_GHC_TAR}" -C "${TERMUX_GHC_RUNTIME_FOLDER}"

		# Replace ghc settings with settings of the cross compiler.
		sed "s|\$topdir/bin/unlit|${TERMUX_GHC_RUNTIME_FOLDER}/lib/ghc-${TERMUX_GHC_VERSION}/bin/unlit|g" \
			"${TERMUX_GHC_RUNTIME_FOLDER}/lib/ghc-${TERMUX_GHC_VERSION}/settings" > \
			"${TERMUX_PREFIX}/lib/ghc-${TERMUX_GHC_VERSION}/settings"
		# NOTE: Above command edits file in $TERMUX_PREFIX after timestamp is created,
		# so we need to remove it in massage step.

		for tool in ghc ghc-pkg hsc2hs hp2ps ghci; do
			_tool="${tool}"
			[[ "${tool}" == "ghci" ]] && _tool="ghc"
			sed -i "s|\$executablename|${TERMUX_GHC_RUNTIME_FOLDER}/lib/ghc-${TERMUX_GHC_VERSION}/bin/${_tool}|g" \
				"${TERMUX_GHC_RUNTIME_FOLDER}/bin/termux-${tool}"
		done

		# GHC ships with old version, we use our own.
		termux-ghc-pkg unregister Cabal
		# NOTE: Above command rewrites a cache file at
		# "${TERMUX_PREFIX}/lib/ghc-${TERMUX_GHC_VERSION}/package.conf.d". Since it is done after
		# timestamp creation, we need to remove it in massage step.

		__termux_haskell_setup_build_script "${TERMUX_GHC_RUNTIME_FOLDER}"
		__termux_haskell_register_packages

		rm "${TERMUX_GHC_TAR}"
	else

		if [[ "${TERMUX_APP_PACKAGE_MANAGER}" == "apt" ]] && "$(dpkg-query -W -f '${db:Status-Status}\n' ghc 2>/dev/null)" != "installed" ||
			[[ "${TERMUX_APP_PACKAGE_MANAGER}" == "pacman" ]] && ! "$(pacman -Q ghc 2>/dev/null)"; then
			echo "Package 'ghc' is not installed."
			exit 1
		else
			local ON_DEVICE_GHC_RUNTIME="${TERMUX_COMMON_CACHEDIR}/${GHC_PREFIX}-runtime"
			export PATH="${ON_DEVICE_GHC_RUNTIME}/bin:${PATH}"

			if [[ -d "${ON_DEVICE_GHC_RUNTIME}" ]]; then
				__termux_haskell_setup_build_script "${ON_DEVICE_GHC_RUNTIME}"
				__termux_haskell_register_packages
				return
			fi

			mkdir -p "${ON_DEVICE_GHC_RUNTIME}"/bin
			for tool in ghc ghc-pkg hsc2hs hp2ps ghci; do
				ln -sf "${TERMUX_PREFIX}/bin/${tool}" "${ON_DEVICE_GHC_RUNTIME}/bin/termux-${tool}"
			done
			__termux_haskell_setup_build_script "${ON_DEVICE_GHC_RUNTIME}"
			__termux_haskell_register_packages
		fi
	fi
}
