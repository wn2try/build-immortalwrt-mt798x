REQUIRE_IMAGE_METADATA=1
RAMFS_COPY_BIN='fitblk fit_check_sign'

platform_do_upgrade() {
	fit_do_upgrade "$1"
}

platform_check_image() {
	[ "$#" -gt 1 ] && return 1

	fit_check_image "$1"
	return $?

	return 0
}
