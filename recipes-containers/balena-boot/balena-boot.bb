SUMMARY = "Boot partition creation recipe"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"
inherit deploy balena-boot-helpers

# kernel deploys the dtb and the overlays
# plymouth brings in the boot logo and nm
# deploys the nm connection file
DEPENDS = " \
    tar-native \
    ${BALENA_IMAGE_BOOTLOADER} \
"

S = "${WORKDIR}"

BALENA_DOCKER_BOOT_IMG = "balena-boot.docker"
BALENA_BOOT_WORK_DIR="${B}/work/boot"

do_compile () {
    rm -rf ${B}/work

    # Provided by balena-boot-helpers.bbclass
    boot_dirgen

    DOCKER_IMAGE=$(tar -cv -C ${BALENA_BOOT_WORK_DIR} . | DOCKER_API_VERSION=1.22 docker import \
        -c "LABEL io.balena.image.class=fileset" \
        -c "LABEL io.balena.image.store=boot" \
        -c "LABEL io.balena.image.requires-reboot=1" -)

    DOCKER_API_VERSION=1.22 docker save "${DOCKER_IMAGE}" > ${B}/work/${BALENA_DOCKER_BOOT_IMG}
    DOCER_API_VERSION=1.22 docker rmi "${DOCKER_IMAGE}"
}

do_deploy () {
    install -m 644 ${B}/work/${BALENA_DOCKER_BOOT_IMG} ${DEPLOYDIR}/
}

# Provided by balena-boot-helpers.bbclass
addhandler overlay_dtbs_handler
overlay_dtbs_handler[eventmask] = "bb.event.RecipePreFinalise"

do_compile[depends] += " \
    virtual/kernel:do_deploy \
    virtual/bootloader:do_deploy \
    plymouth:do_deploy \
    networkmanager:do_deploy \
    ${@bb.utils.contains('RPI_USE_U_BOOT', '1', 'rpi-u-boot-scr:do_deploy', '',d)} \
"

addtask deploy after do_compile
