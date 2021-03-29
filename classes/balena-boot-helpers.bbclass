DEPENDS_append = "\
    jq-native \
"

# These are common for all Balena images
BALENA_BOOT_PARTITION_FILES_append = " \
    balena-logo.png:/splash/balena-logo.png \
    os-release:/os-release \
"
BALENA_BOOT_PARTITION_FILES_append = " ${BALENA_COREBASE}/../../../${MACHINE}.json:/device-type.json"

# Example NetworkManager config file
BALENA_BOOT_PARTITION_FILES_append = " \
    system-connections/resin-sample.ignore:/system-connections/resin-sample.ignore \
    system-connections/README.ignore:/system-connections/README.ignore \
"

# Initialize config.json - borrowed from image-balena.bbclass
# Requires 1 argument: Path to destination of config.json
init_config_json() {
   if [ -z ${1} ]; then
       bbfatal "init_config_json: Needs one argument, that has to be a path"
   fi

   echo '{}' > ${1}/config.json

   # Default no to persistent-logging
   echo "$(cat ${1}/config.json | jq -S ".persistentLogging=false")" > ${1}/config.json

   # Default localMode to true
   echo "$(cat ${1}/config.json | jq -S ".localMode=true")" > ${1}/config.json

   # Find board json and extract slug
   json_path=${BALENA_COREBASE}/../../../${MACHINE}.json
   slug=$(jq .slug $json_path)

   # Set deviceType for supervisor
   echo "$(cat ${1}/config.json | jq -S ".deviceType=$slug")" > ${1}/config.json

   if ${@bb.utils.contains('DISTRO_FEATURES','development-image','true','false',d)}; then
       echo "$(cat ${1}/config.json | jq -S ".hostname=\"balena\"")" > ${1}/config.json
   fi
}

# Generate a boot partition directory - borrowed from imge-balena.bbclass, originally named "resin_boot_dirgen_and_deploy"
boot_dirgen () {
    echo "Generating work directory for resin-boot partition..."
    rm -rf ${BALENA_BOOT_WORK_DIR}
    for BALENA_BOOT_PARTITION_FILE in ${BALENA_BOOT_PARTITION_FILES}; do
        echo "Handling $BALENA_BOOT_PARTITION_FILE ."

        # Check for item format
        case $BALENA_BOOT_PARTITION_FILE in
            *:*) ;;
            *) bbfatal "Some items in BALENA_BOOT_PARTITION_FILES ($BALENA_BOOT_PARTITION_FILE) are not in the 'src:dst' format."
        esac

        # Compute src and dst
        src="$(echo ${BALENA_BOOT_PARTITION_FILE} | awk -F: '{print $1}')"
        if [ -z "${src}" ]; then
            bbfatal "An entry in BALENA_BOOT_PARTITION_FILES has no source. Entries need to be in the \"src:dst\" format where only \"dst\" is optional. Failed entry: \"$BALENA_BOOT_PARTITION_FILE\"."
        fi
        dst="$(echo ${BALENA_BOOT_PARTITION_FILE} | awk -F: '{print $2}')"
        if [ -z "${dst}" ]; then
            dst="/${src}" # dst was omitted
        fi
        case $src in
            /* )
                # Use absolute src paths as they are
                ;;
            *)
                # Relative src paths are considered relative to deploy dir
                src="${DEPLOY_DIR_IMAGE}/$src"
                ;;
        esac

        # Check that dst is an absolute path and assess if it should be a directory
        case $dst in
            /*)
                # Check if dst is a directory. Directory path ends with '/'.
                case $dst in
                    */) dst_is_dir=true ;;
                     *) dst_is_dir=false ;;
                esac
                ;;
             *) bbfatal "$dst in BALENA_BOOT_PARTITION_FILES is not an absolute path."
        esac

        # Check src type and existence
        if [ -d "$src" ]; then
            if ! $dst_is_dir; then
                bbfatal "You can't copy a directory to a file. You requested to copy $src in $dst."
            fi
            sources="$(find $src -maxdepth 1 -type f)"
        elif [ -f "$src" ]; then
            sources="$src"
        else
            bbfatal "$src is an invalid path referenced in BALENA_BOOT_PARTITION_FILES."
        fi
       # Normalize paths
        dst=$(realpath -ms $dst)
        if $dst_is_dir && [ ! "$dst" = "/" ]; then
            dst="$dst/" # realpath removes last '/' which we need to instruct mcopy that destination is a directory
        fi
        src=$(realpath -m $src)

        for src in $sources; do
            echo "Copying $src -> $dst ..."
            # Create the directories parent directories in dst
            directory=""
            for path_segment in $(echo ${BALENA_BOOT_WORK_DIR}/${dst} | sed 's|/|\n|g' | head -n -1); do
                if [ -z "$path_segment" ]; then
                    continue
                fi
                directory=$directory/$path_segment
                mkdir -p $directory
            done
            cp -rvfL $src ${BALENA_BOOT_WORK_DIR}/$dst
       done
    done
    echo "${IMAGE_NAME}" > ${BALENA_BOOT_WORK_DIR}/image-version-info
    init_config_json ${BALENA_BOOT_WORK_DIR}

    # Keep this after everything is ready in the resin-boot directory
    find ${BALENA_BOOT_WORK_DIR} -xdev -type f \
        ! -name ${BALENA_FINGERPRINT_FILENAME}.${BALENA_FINGERPRINT_EXT} \
        ! -name config.json \
        -exec md5sum {} \; | sed "s#${BALENA_BOOT_WORK_DIR}##g" | \
        sort -k2 > ${BALENA_BOOT_WORK_DIR}/${BALENA_FINGERPRINT_FILENAME}.${BALENA_FINGERPRINT_EXT}
}

# Borrowed from meta-raspberrypi/sdcard_image-rpi.bbclass
def split_overlays(d, out, ver=None):
    dts = d.getVar("KERNEL_DEVICETREE")
    # Device Tree Overlays are assumed to be suffixed by '-overlay.dtb' (4.1.x) or by '.dtbo' (4.4.9+) string and will be put in a dedicated folder
    if out:
        overlays = oe.utils.str_filter_out('\S+\-overlay\.dtb$', dts, d)
        overlays = oe.utils.str_filter_out('\S+\.dtbo$', overlays, d)
    else:
        overlays = oe.utils.str_filter('\S+\-overlay\.dtb$', dts, d) + \
                   " " + oe.utils.str_filter('\S+\.dtbo$', dts, d)

    return overlays

# Used for rasperry pi - moved from meta-balena-raspberrypi/balena-image.bbappend
python overlay_dtbs_handler () {
    # Add all the dtb files programatically
    for soc_fam in d.getVar('SOC_FAMILY', True).split(':'):
        if soc_fam == 'rpi':
            resin_boot_partition_files = d.getVar('BALENA_BOOT_PARTITION_FILES', True)

            overlay_dtbs = split_overlays(d, 0)
            root_dtbs = split_overlays(d, 1)

            for dtb in root_dtbs.split():
                dtb = os.path.basename(dtb)
                # newer kernels (5.4 onward) introduce overlay_map.dtb which needs to be deployed in the overlays directory
                if dtb == 'overlay_map.dtb':
                    resin_boot_partition_files += "\t%s:/overlays/%s" % (dtb, dtb)
                    continue
                resin_boot_partition_files += "\t%s:/%s" % (dtb, dtb)

            for dtb in overlay_dtbs.split():
                dtb = os.path.basename(dtb)
                resin_boot_partition_files += "\t%s:/overlays/%s" % (dtb, dtb)

            d.setVar('BALENA_BOOT_PARTITION_FILES', resin_boot_partition_files)

            break
}

