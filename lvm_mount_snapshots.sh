#!/bin/bash

SNAPSHOT_MOUNT_POINT='/mnt/snapshots'
SNAPSHOT_MOUNT_OPTIONS='nouuid,ro' # xfs needs nouuid
SNAPSHOT_SIZE='50%ORIGIN'
SNAPSHOT_PREFIX='snap_'
DEFAULT_VOLUME_GROUP='vg00'
REQUIREMENTS="/sbin/lvremove /sbin/lvcreate /sbin/lvs"

get_volumes(){
    LVS=$(/sbin/lvs --separator / --noheadings -o vg_name,lv_name 2>&- | tr -d ' ') || true
    echo $LVS
}

find_volume(){
    local target volume_group volumes volume
    target=$1
    volume_group=$DEFAULT_VOLUME_GROUP
    test -z $target && return 1
    if [[ $# -eq 2 ]]; then
        volume_group=$2
    fi
    test -z $volume_group && return 1
    volumes=$(get_volumes)
    test -z volume && return 1
    for volume in $volumes; do
        if [[ "${volume}" == "${volume_group}/${target}" ]]; then
                echo $volume
                return 0
        fi
    done
    return 1
}

make_snapshot(){
    local volume name size
    volume=$1
    name=$2
    size=$3
    test -z $volume && return 1
    test -z $name && return 1
    test -z $size && return 1
    echo "INFO: LVM creating $name for $volume"
    /sbin/lvcreate -n $name --extents "${size}" -s $volume
}

remove_snapshot(){
    local volume
    volume=$1
    test -z $volume && return 1
    echo "INFO: LVM removing ${volume}"
    /sbin/lvremove -f ${volume}
}

mount_snapshot(){
    local device mount_target mount_options mount_args
    device=$1
    mount_target=$2
    mount_options=$3
    test -z $device && return 1
    test -z $mount_target && return 1
    mount_args="${device} ${mount_target}"
    test -n $mount_options && mount_args="-o ${mount_options} ${mount_args}"
    create_mountpoint $mount_target
    echo "INFO: mounting $mount_args"
    mount $mount_args
}

unmount_snapshot(){
    local mount_target
    mount_target=$1
    test -z $mount_target && return 1
    echo "INFO: unmounting $mount_target"
    umount $mount_target
}

is_mounted(){
    local mount_target ret
    mount_target=$1
    test -z $mount_target && return 1
    result=$(awk "{ if (\$2 == \"${mount_target}\") { print \$1 } }" /proc/mounts)
    if [[ -n $result ]]; then
        return 0
    else
        return 1
    fi
}

create_mountpoint(){
    local mount_target
    mount_target=$1
    test -z $mount_target && return 1
    test -d $mount_target || mkdir -p $mount_target
}

check_requirements(){
    local errorcnt req requirements
    requirements=$1
    errorcnt=0
    for req in $requirements; do
        test -x $req && continue
        ret=$?
        test $ret -eq 0 || let errorcnt=errorcnt+1
        test $ret -eq 0 || echo "${req} is missing"
    done
    test $errorcnt -gt 0 && echo "ERROR: requirements failed" && exit $errorcnt
}

usage(){
    echo "USAGE: ${0} mode lvm_target [volume_group]"
    echo "    mode: (mount|unmount)"
    echo "    lvm_target: volume"
    echo "    volume_group: vgroup (default=${DEFAULT_VOLUME_GROUP})"
    test -n $1 && exit $1
}

if [[ $# -lt 2 ]]; then
    usage 1
fi
if [[ $# -eq 3 ]]; then
    volume_group=$3
else
    volume_group=$DEFAULT_VOLUME_GROUP
fi

check_requirements $REQUIREMENTS

mode=$1
target=$2
volume_target="${volume_group}/${2}"
snapshot_name="${SNAPSHOT_PREFIX}${target}"
snapshot_mount_name="${volume_group}-${snapshot_name}"
snapshot_mount_device="/dev/mapper/${snapshot_mount_name}"
snapshot_mount_target="${SNAPSHOT_MOUNT_POINT}/${snapshot_mount_name}"

case $mode in
    'mount')
            snapshot_vol=$(find_volume $snapshot_name $volume_group)
            if [[ -n $snapshot_vol ]]; then
                echo "ERROR: found old snapshot volume, please remove it before creating new"
                exit 2
            fi
            is_mounted $snapshot_mount_target && unmount_snapshot $snapshot_mount_target
            volume=$(find_volume $volume_target $volume_group)
            if [[ -z $volume ]]; then
                echo "ERROR: failed to find volume ${volume_target}"
                exit $ret
            fi
            make_snapshot $volume $snapshot_name $SNAPSHOT_SIZE
            ret=$?
            if [[ $ret != 0 ]]; then
                echo "ERROR: failed to create snapshot ${snapshot_name} for volume ${volume}"
                exit $ret
            fi
            mount_snapshot $snapshot_mount_device $snapshot_mount_target $SNAPSHOT_MOUNT_OPTIONS
        ;;
    'unmount')
            is_mounted $snapshot_mount_target && unmount_snapshot $snapshot_mount_target
            snapshot=$(find_volume $snapshot_name $volume_group)
            test -z $snapshot || remove_snapshot $snapshot || exit 0
        ;;
    *)
            echo "WARN: unknown mode"
            usage 3
        ;;
esac