SUMMARY = "Kernel image fileset creation recipe"
LICENSE = "Apache-2.0"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/Apache-2.0;md5=89aea4e17d99a7cacdbeed46a0096b10"

inherit deploy

DEPENDS = " \
    tar-native \
"

S = "${WORKDIR}"

BALENA_DOCKER_KERNEL_IMG = "balena-kernel.docker"
BALENA_KERNEL_WORK_DIR="${B}/work/kernel"

do_compile () {
    rm -rf ${B}/work
    mkdir -p ${BALENA_KERNEL_WORK_DIR}/boot

    for type in ${KERNEL_IMAGETYPE}; do
        cp ${DEPLOY_DIR_IMAGE}/${type}-initramfs-${MACHINE}.bin ${BALENA_KERNEL_WORK_DIR}/boot/${type}
    done

    DOCKER_IMAGE=$(tar -cv -C ${BALENA_KERNEL_WORK_DIR} . | DOCKER_API_VERSION=1.22 docker import \
        -c "LABEL io.balena.image.class=fileset" \
        -c "LABEL io.balena.image.store=root" \
        -c "LABEL io.balena.image.requires-reboot=1" -)

    DOCKER_API_VERSION=1.22 docker save ${DOCKER_IMAGE} > ${B}/work/${BALENA_DOCKER_KERNEL_IMG}
    DOCKER_API_VERSION=1.22 docker rmi "$DOCKER_IMAGE"
}

do_deploy () {
    install -m 644 ${B}/work/${BALENA_DOCKER_KERNEL_IMG} ${DEPLOYDIR}/
}

do_compile[depends] += " \
    virtual/kernel:do_deploy \
"

addtask deploy after do_compile
