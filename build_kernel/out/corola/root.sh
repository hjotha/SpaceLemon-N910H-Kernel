#!/sbin/sh
#
# SuperSU installer ZIP
# Copyright (c) 2012-2016 - Chainfire
#
# ----- GENERIC INFO ------
#
# The following su binary versions are included in the full package. Each
# should be installed only if the system has the same or newer API level
# as listed. The script may fall back to a different binary on older API
# levels. supolicy are all ndk/pie/19+ for 32 bit, ndk/pie/20+ for 64 bit.
#
# binary        ARCH/path   build type      API
#
# arm-v5te      arm         ndk non-pie     7+
# x86           x86         ndk non-pie     7+
#
# x86           x86         ndk pie         17+   (su.pie, naming exception)
# arm-v7a       armv7       ndk pie         17+
# mips          mips        ndk pie         17+
#
# arm64-v8a     arm64       ndk pie         20+
# mips64        mips64      ndk pie         20+
# x86_64        x64         ndk pie         20+
#
# Non-static binaries are supported to be PIE (Position Independent
# Executable) from API level 16, and required from API level 20 (which will
# refuse to execute non-static non-PIE).
#
# The script performs several actions in various ways, sometimes
# multiple times, due to different recoveries and firmwares behaving
# differently, and it thus being required for the correct result.
#
# Overridable variables (shell):
#   BIN - Location of architecture specific files (native folder)
#   COM - Location of common files (APK folder)
#   LESSLOGGING - Reduce ui_print logging (true/false)
#   NOOVERRIDE - Do not read variables from /system/.supersu or
#                /data/.supersu
#
# Overridable variables (shell, /system/.supersu, /cache/.supersu,
# /data/.supersu):
#   SYSTEMLESS - Do a system-less install? (true/false, 6.0+ only)
#   PATCHBOOTIMAGE - Automatically patch boot image? (true/false,
#                    SYSTEMLESS only)
#   BOOTIMAGE - Boot image location (PATCHBOOTIMAGE only)
#   STOCKBOOTIMAGE - Stock boot image location (PATCHBOOTIMAGE only)
#   BINDSYSTEMXBIN - Poor man's overlay on /system/xbin (true/false,
#                    SYSTEMLESS only)
#   PERMISSIVE - Set sepolicy to fake-permissive (true/false, PATCHBOOTIMAGE
#                only)
#   KEEPVERITY - Do not remove dm-verity (true/false, PATCHBOOTIMAGE only)
#   KEEPFORCEENCRYPT - Do not replace forceencrypt with encryptable (true/
#                      false, PATCHBOOTIMAGE only)
#   FRP - Place files in boot image that allow root to survive a factory
#         reset (true/false, PATCHBOOTIMAGE only). Reverts to su binaries
#         from the time the ZIP was originall flashed, updates are lost.
# Shell overrides all, /data/.supersu overrides /cache/.supersu overrides
# /system/.supersu
#
# Note that if SELinux is set to enforcing, the daemonsu binary expects
# to be run at startup (usually from install-recovery.sh, 99SuperSUDaemon,
# or app_process) from u:r:init:s0 or u:r:kernel:s0 contexts. Depending
# on the current policies, it can also deal with u:r:init_shell:s0 and
# u:r:toolbox:s0 contexts. Any other context will lead to issues eventually.
#
# ----- "SYSTEM" INSTALL -----
#
# "System" install puts all the files needed in /system and does not need
# any boot image modifications. Default install method pre-Android-6.0
# (excluding Samsung-5.1).
#
# Even on Android-6.0+, the script attempts to detect if the current
# firmware is compatible with a system-only installation (see the
# "detect_systemless_required" function), and will prefer that
# (unless the SYSTEMLESS variable is set) if so. This will catch the
# case of several custom ROMs that users like to use custom boot images
# with - SuperSU will not need to patch these. It can also catch some
# locked bootloader cases that do allow security policy updates.
#
# To install SuperSU properly, aside from cleaning old versions and
# other superuser-type apps from the system, the following files need to
# be installed:
#
# API   source                        target                              chmod   chcon                       required
#
# 7-19  common/Superuser.apk          /system/app/Superuser.apk           0644    u:object_r:system_file:s0   gui
# 20+   common/Superuser.apk          /system/app/SuperSU/SuperSU.apk     0644    u:object_r:system_file:s0   gui
#
# 17+   common/install-recovery.sh    /system/etc/install-recovery.sh     0755    *1                          required
# 17+                                 /system/bin/install-recovery.sh     (symlink to /system/etc/...)        required
# *1: same as /system/bin/toolbox: u:object_r:system_file:s0 if API < 20, u:object_r:toolbox_exec:s0 if API >= 20
#
# 7+    ARCH/su *2                    /system/xbin/su                     *3      u:object_r:system_file:s0   required
# 7+                                  /system/bin/.ext/.su                *3      u:object_r:system_file:s0   gui
# 17+                                 /system/xbin/daemonsu               0755    u:object_r:system_file:s0   required
# 17-21                               /system/xbin/sugote                 0755    u:object_r:zygote_exec:s0   required
# *2: su.pie for 17+ x86(_32) only
# *3: 06755 if API < 18, 0755 if API >= 18
#
# 19+   ARCH/supolicy                 /system/xbin/supolicy               0755    u:object_r:system_file:s0   required
# 19+   ARCH/libsupol.so              /system/lib(64)/libsupol.so         0644    u:object_r:system_file:s0   required
#
# 17-21 /system/bin/sh or mksh *4     /system/xbin/sugote-mksh            0755    u:object_r:system_file:s0   required
# *4: which one (or both) are available depends on API
#
# 21+   /system/bin/app_process32 *5  /system/bin/app_process32_original  0755    u:object_r:zygote_exec:s0   required
# 21+   /system/bin/app_process64 *5  /system/bin/app_process64_original  0755    u:object_r:zygote_exec:s0   required
# 21+   /system/bin/app_processXX *5  /system/bin/app_process_init        0755    u:object_r:system_file:s0   required
# 21+                                 /system/bin/app_process             (symlink to /system/xbin/daemonsu)  required
# 21+                             *5  /system/bin/app_process32           (symlink to /system/xbin/daemonsu)  required
# 21+                             *5  /system/bin/app_process64           (symlink to /system/xbin/daemonsu)  required
# *5: Only do this for the relevant bits. On a 64 bits system, leave the 32 bits files alone, or dynamic linker errors
#     will prevent the system from fully working in subtle ways. The bits of the su binary must also match!
#
# 17+   common/99SuperSUDaemon *6     /system/etc/init.d/99SuperSUDaemon  0755    u:object_r:system_file:s0   optional
# *6: only place this file if /system/etc/init.d is present
#
# 17+   'echo 1 >' or 'touch' *7      /system/etc/.installed_su_daemon    0644    u:object_r:system_file:s0   optional
# *7: the file just needs to exist or some recoveries will nag you. Even with it there, it may still happen.
#
# It may seem some files are installed multiple times needlessly, but
# it only seems that way. Installing files differently or symlinking
# instead of copying (unless specified) will lead to issues eventually.
#
# After installation, run '/system/xbin/su --install', which may need to
# perform some additional installation steps. Ideally, at one point,
# a lot of this script will be moved there.
#
# The included chattr(.pie) binaries are used to remove ext2's immutable
# flag on some files. This flag is no longer set by SuperSU's OTA
# survival since API level 18, so there is no need for the 64 bit versions.
# Note that chattr does not need to be installed to the system, it's just
# used by this script, and not supported by the busybox used in older
# recoveries.
#
# ----- "SYSTEM-LESS" INSTALL -----
#
# "System-less" install requires a modified boot image (the script can patch
# many boot images on-the-fly), but does not touch /system at all. Instead
# it keeps all the needed files in an image (/data/su.img) which is mounted
# to /su. Default install method on all Android-6.0+ and Samsung-5.1+
# devices.
#
# Note that even on 6.0+, system compatibility is checked. See the "SYSTEM"
# install section above.
#
# An ext4 image is created as /data/su.img, or /cache/su.img if /data could
# not be mounted. Similarly, the APK is placed as either /data/SuperSU.apk
# or /cache/SuperSU.apk. This is so we are not dependent on /data decryption
# working in recovery, which in the past has proved an issue on brand-new
# Android versions and devices.
#
# /sbin/launch_daemonsu.sh, which is added a service to init.rc, will mount
# the image at /su, and launch daemonsu from /su/bin/daemonsu. But before it
# does that, it will try to merge /data/su.img and /cache/su.img (leading),
# if both are present. It will also try to install the SuperSU APK.
#
# Files are expected at the following places (/su being the mountpoint of
# the ext4 image):
#
# API   source                        target                              chmod   chcon                       required
#
# 22+   common/Superuser.apk          /[data|cache]/SuperSU.apk           0644    u:object_r:system_file:s0   gui
#
# 22+   ARCH/su *1                    /su/bin/su                          0755    u:object_r:system_file:s0   required
# 22+                                 /su/bin/daemonsu                    0755    u:object_r:system_file:s0   required
# *1: su.pie for 17+ x86(_32) only
#
# 22+   ARCH/supolicy                 /su/bin/supolicy_wrapped            0755    u:object_r:system_file:s0   required
# 22+   /su/bin/su (symlink) *2       /su/bin/supolicy                    0755    u:object_r:system_file:s0   required
# 22+   ARCH/libsupol.so              /su/lib/libsupol.so                 0644    u:object_r:system_file:s0   required
# *2: when called this way, su sets the correct LD_LIBRARY_PATH and calls supolicy_wrapped
#
# 22+   ARCH/sukernel                 /su/bin/sukernel                    0755    u:object_r:system_file:s0   required
#
# These files are automatically created on launch by daemonsu as needed:
# 22+   /system/bin/sh                /su/bin/sush                        0755    u:object_r:system_file:s0   required
# 22+   /system/bin/app_process[64]   /su/bin/app_process                 0755    u:object_r:system_file:s0   required
#
# These files are injected into the boot image ramdisk:
# 22+   common/launch_daemonsu.sh     /sbin/launch_daemonsu.sh            0700    u:object_r:rootfs:s0        required
#
# On devices where / is in the system partition:
# 22+   ARCH/suinit                   /init                               0750    u:object_r:rootfs:s0        required
#
# The automated boot image patcher included makes the following modifications
# to the ramdisk:
#
# - Uses the supolicy tool to patch the sepolicy file
# - Injects /sbin/launch_daemon.sh
# - Creates /su
# - Removes /verity_key
# - Patches /*fstab*
# --- Removes support_scfs and verify flags
# --- Changes forceencrypt/forcefdeorfbe into encryptable
# --- Set ro mounts to use noatime
# - Patches /init.rc
# --- Removes 'setprop selinux.reload_policy' occurences
# --- Adds a SuperSU:PATCH marker with the version of the sukernel tool
# --- Adds a SuperSU:STOCK marker listed the SHA1 of the original boot image
# - Adds /init.supersu.rc
# --- Adds a sukernel.mount property trigger that mounts /data/su.img to /su
# --- Adds the daemonsu service that launches /sbin/launch_daemon.sh
# --- Adds exec /sbin/launch_daemonsu.sh on post-fs-data
# - Patches /init.environ.rc
# --- Adds PATH variable if it does not exist
# --- Prepends /su/bin to the PATH variable
# - Patches /*.rc
# --- Adds a seclabel to services and execs that are missing one
# - Patches /file_contexts[.bin]
# --- Adds a default context for file existing in the /su mount
# - In case the device has the root directory inside the system partition:
# --- /system_root contents are copied to /boot
# --- All files mentioned above are modified in /boot instead of /
# --- /boot/*fstab* is modified to mount / to /system_root
# --- /system is symlinked to /system_root/system
# --- Kernel binary is patched to load from initramfs instead of system
#
# In case this documentation becomes outdated, please note that the sukernel
# tool is very chatty, and its output tells you exactly what it is doing
# and how. In TWRP, you can view this output by catting /tmp/recovery.log
# after flashing the ZIP.
#
# The boot image patcher creates a backup of the boot image it patches, for
# future restoration. It cannot re-patch a patched boot image, it will restore
# the previous boot image first. /[data|cache]/stock_boot_*.gz
#
# The boot image patcher currently only supports GZIP compressed ramdisks, and
# boot images in the standard Android boot image format.
#
# During boot image patch, /data/custom_ramdisk_patch.sh will be called,
# with the name of the ramdisk cpio file as parameter. The script must
# replace the input file and return a 0 exit code.
#
# Just before flashing, the boot image patcher will call
# /data/custom_boot_image_patch.sh with the name of the patched boot image
# as parameter. A device-specific patcher can further patch the boot image
# if needed. It must replace the input file and return a 0 exit code.

OUTFD=$2
ZIP=$3

getvar() {
  local VARNAME=$1
  local VALUE=$(eval echo \$"$VARNAME");
  for FILE in /data/.supersu /cache/.supersu /system/.supersu; do
    if [ -z "$VALUE" ]; then
      LINE=$(cat $FILE 2>/dev/null | grep "$VARNAME=")
      if [ ! -z "$LINE" ]; then
        VALUE=${LINE#*=}
      fi
    fi
  done
  eval $VARNAME=\$VALUE
}

readlink /proc/$$/fd/$OUTFD 2>/dev/null | grep /tmp >/dev/null
if [ "$?" -eq "0" ]; then
  # rerouted to log file, we don't want our ui_print commands going there
  OUTFD=0

  # we are probably running in embedded mode, see if we can find the right fd
  # we know the fd is a pipe and that the parent updater may have been started as
  # 'update-binary 3 fd zipfile'
  for FD in `ls /proc/$$/fd`; do
    readlink /proc/$$/fd/$FD 2>/dev/null | grep pipe >/dev/null
    if [ "$?" -eq "0" ]; then
      ps | grep " 3 $FD " | grep -v grep >/dev/null
      if [ "$?" -eq "0" ]; then
        OUTFD=$FD
        break
      fi
    fi
  done
fi

ui_print_always() {
  echo -n -e "ui_print $1\n" >> /proc/self/fd/$OUTFD
  echo -n -e "ui_print\n" >> /proc/self/fd/$OUTFD
}

if [ -z "$LESSLOGGING" ]; then
  LESSLOGGING=false
fi

UI_PRINT_LAST=""

ui_print() {
  if (! $LESSLOGGING); then
    UI_PRINT_LAST="$1"
    ui_print_always "$1"
  fi
}

ui_print_less() {
  if ($LESSLOGGING); then
    ui_print_always "$1"
  fi
}

ch_con() {
  LD_LIBRARY_PATH=$SYSTEMLIB /system/bin/toybox chcon -h u:object_r:system_file:s0 $1 1>/dev/null 2>/dev/null
  LD_LIBRARY_PATH=$SYSTEMLIB /system/toolbox chcon -h u:object_r:system_file:s0 $1 1>/dev/null 2>/dev/null
  LD_LIBRARY_PATH=$SYSTEMLIB /system/bin/toolbox chcon -h u:object_r:system_file:s0 $1 1>/dev/null 2>/dev/null
  chcon -h u:object_r:system_file:s0 $1 1>/dev/null 2>/dev/null
  LD_LIBRARY_PATH=$SYSTEMLIB /system/bin/toybox chcon u:object_r:system_file:s0 $1 1>/dev/null 2>/dev/null
  LD_LIBRARY_PATH=$SYSTEMLIB /system/toolbox chcon u:object_r:system_file:s0 $1 1>/dev/null 2>/dev/null
  LD_LIBRARY_PATH=$SYSTEMLIB /system/bin/toolbox chcon u:object_r:system_file:s0 $1 1>/dev/null 2>/dev/null
  chcon u:object_r:system_file:s0 $1 1>/dev/null 2>/dev/null
}

ch_con_ext() {
  LD_LIBRARY_PATH=$SYSTEMLIB /system/bin/toybox chcon $2 $1 1>/dev/null 2>/dev/null
  LD_LIBRARY_PATH=$SYSTEMLIB /system/toolbox chcon $2 $1 1>/dev/null 2>/dev/null
  LD_LIBRARY_PATH=$SYSTEMLIB /system/bin/toolbox chcon $2 $1 1>/dev/null 2>/dev/null
  chcon $2 $1 1>/dev/null 2>/dev/null
}

ln_con() {
  LD_LIBRARY_PATH=$SYSTEMLIB /system/bin/toybox ln -s $1 $2 1>/dev/null 2>/dev/null
  LD_LIBRARY_PATH=$SYSTEMLIB /system/toolbox ln -s $1 $2 1>/dev/null 2>/dev/null
  LD_LIBRARY_PATH=$SYSTEMLIB /system/bin/toolbox ln -s $1 $2 1>/dev/null 2>/dev/null
  ln -s $1 $2 1>/dev/null 2>/dev/null
  ch_con $2 1>/dev/null 2>/dev/null
}

set_perm() {
  chown $1.$2 $4
  chown $1:$2 $4
  chmod $3 $4
  ch_con $4
  ch_con_ext $4 $5
}

cp_perm() {
  rm $5
  if [ -f "$4" ]; then
    cat $4 > $5
    set_perm $1 $2 $3 $5 $6
  fi
}

is_mounted() {
  if [ ! -z "$2" ]; then
    cat /proc/mounts | grep $1 | grep $2, >/dev/null
  else
    cat /proc/mounts | grep $1 >/dev/null
  fi
  return $?
}

toolbox_mount() {
  RW=rw
  if [ ! -z "$2" ]; then
    RW=$2
  fi

  DEV=
  POINT=
  FS=
  for i in `cat /etc/fstab | grep "$1"`; do
    if [ -z "$DEV" ]; then
      DEV=$i
    elif [ -z "$POINT" ]; then
      POINT=$i
    elif [ -z "$FS" ]; then
      FS=$i
      break
    fi
  done
  if (! is_mounted $1 $RW); then mount -t $FS -o $RW $DEV $POINT; fi
  if (! is_mounted $1 $RW); then mount -t $FS -o $RW,remount $DEV $POINT; fi

  DEV=
  POINT=
  FS=
  for i in `cat /etc/recovery.fstab | grep "$1"`; do
    if [ -z "$POINT" ]; then
      POINT=$i
    elif [ -z "$FS" ]; then
      FS=$i
    elif [ -z "$DEV" ]; then
      DEV=$i
      break
    fi
  done
  if [ "$FS" = "emmc" ]; then
    if (! is_mounted $1 $RW); then mount -t ext4 -o $RW $DEV $POINT; fi
    if (! is_mounted $1 $RW); then mount -t ext4 -o $RW,remount $DEV $POINT; fi
    if (! is_mounted $1 $RW); then mount -t f2fs -o $RW $DEV $POINT; fi
    if (! is_mounted $1 $RW); then mount -t f2fs -o $RW,remount $DEV $POINT; fi
  else
    if (! is_mounted $1 $RW); then mount -t $FS -o $RW $DEV $POINT; fi
    if (! is_mounted $1 $RW); then mount -t $FS -o $RW,remount $DEV $POINT; fi
  fi
}

remount_system_rw() {
  if (! is_mounted /system rw); then mount -o rw,remount /system; fi
  if (! is_mounted /system rw); then mount -o rw,remount /system /system; fi
  if (! is_mounted /system rw); then toolbox_mount /system; fi
}

# 'readlink -f' is not reliable across devices/recoveries, this works for our case
resolve_link() {
  local RESOLVE=$1
  local RESOLVED=
  while (true); do
    RESOLVED=$(readlink $RESOLVE || echo $RESOLVE)
    if [ "$RESOLVE" = "$RESOLVED" ]; then
      echo $RESOLVE
      break
    else
      RESOLVE=$RESOLVED
    fi
  done
}

wipe_system_files_if_present() {
  GO=false
  SYSTEMFILES="
    /system/xbin/daemonsu
    /system/xbin/sugote
    /system/xbin/sugote-mksh
    /system/xbin/supolicy
    /system/xbin/ku.sud
    /system/xbin/.ku
    /system/xbin/.su
    /system/lib/libsupol.so
    /system/lib64/libsupol.so
    /system/bin/.ext/.su
    /system/etc/init.d/99SuperSUDaemon
    /system/etc/.installed_su_daemon
    /system/app/Superuser.apk
    /system/app/Superuser.odex
    /system/app/Superuser
    /system/app/SuperUser.apk
    /system/app/SuperUser.odex
    /system/app/SuperUser
    /system/app/superuser.apk
    /system/app/superuser.odex
    /system/app/superuser
    /system/app/Supersu.apk
    /system/app/Supersu.odex
    /system/app/Supersu
    /system/app/SuperSU.apk
    /system/app/SuperSU.odex
    /system/app/SuperSU
    /system/app/supersu.apk
    /system/app/supersu.odex
    /system/app/supersu
    /system/app/VenomSuperUser.apk
    /system/app/VenomSuperUser.odex
    /system/app/VenomSuperUser
  "
  for FILE in $SYSTEMFILES; do
    if [ -d "$FILE" ]; then GO=true; fi
    if [ -f "$FILE" ]; then GO=true; fi
  done

  RMSU=false
  if (! $RWSYSTEM); then
    if [ -f "/system/xbin/su" ]; then
      # only remove /system/xbin/su if it's SuperSU. Could be firmware-included version, we
      # do not want to cause remount for that
      SUPERSU_CHECK=$(cat /system/xbin/su | grep SuperSU)
      if [ $? -eq 0 ]; then
        GO=true
        RMSU=true
      fi
    fi

    SPECIALSYSTEMFILES="
      /system/etc/install-recovery_original.sh
      /system/bin/install-recovery_original.sh
      /system/bin/app_process32_original
      /system/bin/app_process32_xposed
      /system/bin/app_process64_original
      /system/bin/app_process64_xposed
      /system/bin/app_process_init
    "
    for FILE in $SPECIALSYSTEMFILES; do
      if [ -d "$FILE" ]; then GO=true; fi
    done
  fi

  if ($GO); then
    if (! $RWSYSTEM); then
      ui_print "- Remounting system r/w :("
      remount_system_rw
    fi

    for FILE in $SYSTEMFILES; do
      if [ -d "$FILE" ]; then rm -rf $FILE; fi
      if [ -f "$FILE" ]; then rm -f $FILE; fi
    done

    if (! $RWSYSTEM); then
      # remove wrongly placed /system/xbin/su as well
      if ($RMSU); then
        rm -f /system/xbin/su
      fi

      # Restore install-recovery and app_process from system install
      # Otherwise, our system-less install will fail to boot
      if [ -f "/system/etc/install-recovery_original.sh" ]; then
        rm -f /system/etc/install-recovery.sh
        mv /system/etc/install-recovery_original.sh /system/etc/install-recovery.sh
      fi
      if [ -f "/system/bin/install-recovery_original.sh" ]; then
        rm -f /system/bin/install-recovery.sh
        mv /system/bin/install-recovery_original.sh /system/bin/install-recovery.sh
      fi
      if [ -f "/system/bin/app_process64_original" ]; then
        rm -f /system/bin/app_process64
        if [ -f "/system/bin/app_process64_xposed" ]; then
          ln -s /system/bin/app_process64_xposed /system/bin/app_process64
        else
          mv /system/bin/app_process64_original /system/bin/app_process64
        fi
      fi
      if [ -f "/system/bin/app_process32_original" ]; then
        rm -f /system/bin/app_process32
        if [ -f "/system/bin/app_process32_xposed" ]; then
          ln -s /system/bin/app_process32_xposed /system/bin/app_process32
        else
          mv /system/bin/app_process32_original /system/bin/app_process32
        fi
      fi
      if [ -f "/system/bin/app_process64" ]; then
        rm /system/bin/app_process
        ln -s /system/bin/app_process64 /system/bin/app_process
      elif [ -f "/system/bin/app_process32" ]; then
        rm /system/bin/app_process
        ln -s /system/bin/app_process32 /system/bin/app_process
      fi
      rm -f /system/bin/app_process_init
    fi
  fi
}

wipe_data_competitors_and_cache() {
  rm -f /data/dalvik-cache/*com.noshufou.android.su*
  rm -f /data/dalvik-cache/*/*com.noshufou.android.su*
  rm -f /data/dalvik-cache/*com.koushikdutta.superuser*
  rm -f /data/dalvik-cache/*/*com.koushikdutta.superuser*
  rm -f /data/dalvik-cache/*com.mgyun.shua.su*
  rm -f /data/dalvik-cache/*/*com.mgyun.shua.su*
  rm -f /data/dalvik-cache/*com.m0narx.su*
  rm -f /data/dalvik-cache/*/*com.m0narx.su*
  rm -f /data/dalvik-cache/*com.kingroot.kinguser*
  rm -f /data/dalvik-cache/*/*com.kingroot.kinguser*
  rm -f /data/dalvik-cache/*com.kingroot.master*
  rm -f /data/dalvik-cache/*/*com.kingroot.master*
  rm -f /data/dalvik-cache/*me.phh.superuser*
  rm -f /data/dalvik-cache/*/*me.phh.superuser*
  rm -f /data/dalvik-cache/*Superuser.apk*
  rm -f /data/dalvik-cache/*/*Superuser.apk*
  rm -f /data/dalvik-cache/*SuperUser.apk*
  rm -f /data/dalvik-cache/*/*SuperUser.apk*
  rm -f /data/dalvik-cache/*superuser.apk*
  rm -f /data/dalvik-cache/*/*superuser.apk*
  rm -f /data/dalvik-cache/*VenomSuperUser.apk*
  rm -f /data/dalvik-cache/*/*VenomSuperUser.apk*
  rm -f /data/dalvik-cache/*eu.chainfire.supersu*
  rm -f /data/dalvik-cache/*/*eu.chainfire.supersu*
  rm -f /data/dalvik-cache/*Supersu.apk*
  rm -f /data/dalvik-cache/*/*Supersu.apk*
  rm -f /data/dalvik-cache/*SuperSU.apk*
  rm -f /data/dalvik-cache/*/*SuperSU.apk*
  rm -f /data/dalvik-cache/*supersu.apk*
  rm -f /data/dalvik-cache/*/*supersu.apk*
  rm -f /data/dalvik-cache/*.oat
  rm -rf /data/app/com.noshufou.android.su*
  rm -rf /data/app/com.koushikdutta.superuser*
  rm -rf /data/app/com.mgyun.shua.su*
  rm -rf /data/app/com.m0narx.su*
  rm -rf /data/app/com.kingroot.kinguser*
  rm -rf /data/app/com.kingroot.master*
  rm -rf /data/app/me.phh.superuser*
}

# check_zero "progress_message" "success message" "failure message" "command"
check_zero() {
  if ($CONTINUE); then
    if [ ! -z "$1" ]; then ui_print "$1"; fi
    eval "$4"
    if [ $? -eq 0 ]; then
      if [ ! -z "$2" ]; then ui_print "$2"; fi
    else
      if [ ! -z "$3" ]; then
        if [ ! -z "$1" ]; then
          ui_print_less "$1"
        else
          ui_print_less "$UI_PRINT_LAST"
        fi
        ui_print_always "$3";
      fi
      CONTINUE=false
    fi
  fi
}

# check_zero_def "progress message" "command"
check_zero_def() {
  check_zero "$1" "" "--- Failure, aborting" "$2"
}

# find boot image partition if not set already
find_boot_image() {
  # expand the detection if we find more, instead of reading from fstab, because unroot
  # from the SuperSU APK doesn't have the fstab to read from
  if [ -z "$BOOTIMAGE" ]; then
    for PARTITION in kern-a KERN-A android_boot ANDROID_BOOT kernel KERNEL boot BOOT lnx LNX; do
      BOOTIMAGE=$(readlink /dev/block/by-name/$PARTITION || readlink /dev/block/platform/*/by-name/$PARTITION || readlink /dev/block/platform/*/*/by-name/$PARTITION || readlink /dev/block/by-name/$PARTITION$SLOT_SUFFIX || readlink /dev/block/platform/*/by-name/$PARTITION$SLOT_SUFFIX || readlink /dev/block/platform/*/*/by-name/$PARTITION$SLOT_SUFFIX)
      if [ ! -z "$BOOTIMAGE" ]; then break; fi
    done
  fi
}

# use only on 6.0+, tries to read current boot image and detect if we can do a system install
# without any boot image patching. Requirements:
# - /data readable
# - not pre-patched by SuperSU
# - dm-verity disabled
# - init loads from /data/security/current/sepolicy
# - sepolicy has init load_policy or permissive init
# It symlink/patches the relevant files to /data, and sets SYSTEMLESS variable if not already set
detect_systemless_required() {
  OLD_SYSTEMLESS=$SYSTEMLESS
  if [ "$OLD_SYSTEMLESS" = "detect" ]; then
    # we don't override a pre-set true/false value
    SYSTEMLESS=true
  fi

  # check /data mounted
  if (! is_mounted /data); then
    return
  fi

  # find boot image partition
  find_boot_image

  CONTINUE=true
  if [ -z "$BOOTIMAGE" ]; then
    # no boot image partition detected, abort
    return
  fi

  # extract ramdisk from boot image
  rm -rf /sutmp
  mkdir /sutmp

  check_zero "" "" "" "LD_LIBRARY_PATH=$RAMDISKLIB $BIN/sukernel --bootimg-extract-ramdisk $BOOTIMAGE /sutmp/ramdisk.packed"
  check_zero "" "" "" "LD_LIBRARY_PATH=$RAMDISKLIB $BIN/sukernel --ungzip /sutmp/ramdisk.packed /sutmp/ramdisk"
  if (! $CONTINUE); then return; fi

  # detect SuperSU patch
  LD_LIBRARY_PATH=$RAMDISKLIB $BIN/sukernel --patch-test /sutmp/ramdisk
  if [ $? -ne 0 ]; then
    return
  fi

  # detect dm-verity in use
  for i in `LD_LIBRARY_PATH=$RAMDISKLIB $BIN/sukernel --cpio-ls /sutmp/ramdisk | grep fstab | grep "^${CPIO_PREFIX}"`; do
    rm -f /sutmp/fstab

    check_zero "" "" "" "LD_LIBRARY_PATH=$RAMDISKLIB $BIN/sukernel --cpio-extract /sutmp/ramdisk $i /sutmp/fstab"
    if (! $CONTINUE); then return; fi

    VERIFY=$(cat /sutmp/fstab | grep verify | grep system)
    if [ $? -eq 0 ]; then
      # verify flag found, dm-verity probably enabled, modifying /system may prevent boot
      return
    fi
  done

  # detect init loading from /data/security/current/sepolicy
  check_zero "" "" "" "LD_LIBRARY_PATH=$RAMDISKLIB $BIN/sukernel --cpio-extract /sutmp/ramdisk ${CPIO_PREFIX}init /sutmp/init"
  if (! $CONTINUE); then return; fi

  CURRENT=$(cat /sutmp/init | grep "/data/security/current/sepolicy")
  if [ $? -ne 0 ]; then
    # this init doesn't load from the default sepolicy override location
    return
  fi

  # extract sepolicy
  check_zero "" "" "" "LD_LIBRARY_PATH=$RAMDISKLIB $BIN/sukernel --cpio-extract /sutmp/ramdisk ${CPIO_PREFIX}sepolicy /sutmp/sepolicy"
  if (! $CONTINUE); then return; fi

  GO=false

  # detect init permissive
  if (! $GO); then
    INIT_PERMISSIVE=$(LD_LIBRARY_PATH=$RAMDISKLIB $BIN/supolicy --dumpav /sutmp/sepolicy | grep "[TYPE]" | grep " init (PERMISSIVE) ")
    if [ $? -eq 0 ]; then
      GO=true
    fi
  fi

  # detect init load_policy
  if (! $GO); then
    INIT_LOAD_POLICY=$(LD_LIBRARY_PATH=$RAMDISKLIB $BIN/supolicy --dumpav /sutmp/sepolicy | grep "[AV]" | grep " ALLOW " | grep " init-->kernel (security) " | grep "load_policy")
    if [ $? -eq 0 ]; then
      GO=true
    fi
  fi

  # copy files to /data
  if (! $GO); then return; fi

  rm -rf /data/security/*
  mkdir /data/security/current
  set_perm 1000 1000 0755 /data/security/current u:object_r:security_file:s0

  LD_LIBRARY_PATH=$RAMDISKLIB $BIN/supolicy --file /sutmp/sepolicy /data/security/current/sepolicy
  set_perm 1000 1000 0644 /data/security/current/sepolicy u:object_r:security_file:s0

  for i in seapp_contexts file_contexts file_contexts.bin property_contexts service_contexts selinux_version; do
    ln -s /$i /data/security/current/$i
  done

  ln -s /system/etc/security/mac_permissions.xml /data/security/current/mac_permissions.xml

  # if we reach this point, we can do a system install
  if [ "$OLD_SYSTEMLESS" = "detect" ]; then
    # we don't override a pre-set true/false value
    SYSTEMLESS=false
  fi
}

ui_print " "
ui_print        "*****************"
ui_print_always "SuperSU installer"
ui_print        "*****************"

# detect slot-based partition layout

SLOT_USED=false
SLOT_SUFFIX=$(getprop ro.boot.slot_suffix 2>/dev/null)
SLOT_SYSTEM=
CPIO_PREFIX=
if [ -z "$SLOT_SUFFIX" ]; then
  for i in `cat /proc/cmdline`; do
    if [ "${i%=*}" = "androidboot.slot_suffix" ]; then
      SLOT_SUFFIX=${i#*=}
      break
    fi
  done
fi
if [ ! -z "$SLOT_SUFFIX" ]; then
  SLOT_USED=true
fi
if ($SLOT_USED); then
  # /fstab.* for stock boot images, which can contain slotselect
  # /etc/fstab for TWRP, which will contain $SLOT_SUFFIX

  SYSTEM_FSTAB=$(cat /fstab.* /etc/fstab 2>/dev/null | grep -v "#" | grep -i "/system" | tr -s " ");
  if (! `echo $SYSTEM_FSTAB | grep slotselect >/dev/null 2>&1`); then
    if (! `echo $SYSTEM_FSTAB | grep "$SLOT_SUFFIX" >/dev/null 2>&1`); then
      SLOT_USED=false
    fi
  fi

  if ($SLOT_USED); then
    for i in $SYSTEM_FSTAB; do
      if (! `echo $SYSTEM_FSTAB | grep "$SLOT_SUFFIX" >/dev/null 2>&1`); then
        SLOT_SYSTEM=$i$SLOT_SUFFIX
      else
        SLOT_SYSTEM=$i
      fi
      break
    done
  fi
fi
if ($SLOT_USED); then
  CPIO_PREFIX=boot/
fi

ui_print "- Mounting /system, /data and rootfs"

HAD_SYSTEM=false
HAD_SYSTEM_RW=false
HAD_SYSTEM_ROOT=false
if (`mount | grep " /system " >/dev/null 2>&1`); then
  HAD_SYSTEM=true
  if (`mount | grep " /system " | grep "rw" >/dev/null 2>&1`); then
    HAD_SYSTEM_RW=true
  fi
fi
if (`mount | grep " /system_root " >/dev/null 2>&1`); then
  HAD_SYSTEM_ROOT=true
fi

if (! $SLOT_USED); then
  if (! $HAD_SYSTEM); then
    mount -o ro /system
    toolbox_mount /system ro
  fi
else
  if (! $HAD_SYSTEM_ROOT); then
    # TWRP can have this mounted wrong
    umount /system

    mkdir /system_root
    mount -o ro $SLOT_SYSTEM /system_root
    mount -o bind /system_root/system /system
  fi
fi
mount /data
toolbox_mount /data
mount -o rw,remount /
mount -o rw,remount / /

if [ -z "$BIN" ]; then
  # TWRP went full retard
  if [ ! -f "/sbin/unzip" ]; then
    ui_print "- BAD RECOVERY DETECTED, NO UNZIP, ABORTING"
    exit 1
  fi
fi

if [ -z "$NOOVERRIDE" ]; then
  # read override variables
  getvar SYSTEMLESS
  getvar PATCHBOOTIMAGE
  getvar BOOTIMAGE
  getvar STOCKBOOTIMAGE
  getvar BINDSYSTEMXBIN
  getvar PERMISSIVE
  getvar KEEPVERITY
  getvar KEEPFORCEENCRYPT
  getvar FRP
fi
if [ -z "$SYSTEMLESS" ]; then
  if (! $SLOT_USED); then
    # detect if we need systemless, based on Android version and boot image
    SYSTEMLESS=detect
  else
    # unless we're on a slot-based system, as TWRP being in the same boot image will
    # always cause the detection to default to system-mode
    SYSTEMLESS=true
  fi
fi
if [ -z "$PATCHBOOTIMAGE" ]; then
  # only if we end up doing a system-less install
  PATCHBOOTIMAGE=true
fi
if [ -z "$BINDSYSTEMXBIN" ]; then
  # causes launch_daemonsu to bind over /system/xbin, disabled by default
  BINDSYSTEMXBIN=false
fi
if [ -z "$PERMISSIVE" ]; then
  # don't make everything fake-permissive
  PERMISSIVE=false
fi
if [ -z "$KEEPVERITY" ]; then
  # we don't keep dm-verity by default
  KEEPVERITY=false
fi
if [ -z "$KEEPFORCEENCRYPT" ]; then
  # we don't keep forceencrypt by default
  KEEPFORCEENCRYPT=false
fi
if [ -z "$FRP" ]; then
  # enable FRP if we're using slots, implying large enough boot image
  FRP=$SLOT_USED
fi

API=$(cat /system/build.prop | grep "ro.build.version.sdk=" | dd bs=1 skip=21 count=2)
ABI=$(cat /system/build.prop /default.prop | grep -m 1 "ro.product.cpu.abi=" | dd bs=1 skip=19 count=3)
ABILONG=$(cat /system/build.prop /default.prop | grep -m 1 "ro.product.cpu.abi=" | dd bs=1 skip=19)
ABI2=$(cat /system/build.prop /default.prop | grep -m 1 "ro.product.cpu.abi2=" | dd bs=1 skip=20 count=3)
SUMOD=06755
SUGOTE=false
SUPOLICY=false
INSTALL_RECOVERY_CONTEXT=u:object_r:system_file:s0
MKSH=/system/bin/mksh
PIE=
SU=su
ARCH=arm
APKFOLDER=false
APKNAME=/system/app/Superuser.apk
APPPROCESS=false
APPPROCESS64=false
SYSTEMLIB=/system/lib
RAMDISKLIB=$SYSTEMLIB
RWSYSTEM=true

if [ "$API" -le "21" ]; then
  # needed for some intermediate AOSP verions

  remount_system_rw

  cat /system/bin/toolbox > /system/toolbox
  chmod 0755 /system/toolbox
  ch_con /system/toolbox
fi

if [ "$ABI" = "x86" ]; then ARCH=x86; fi;
if [ "$ABI2" = "x86" ]; then ARCH=x86; fi;
if [ "$API" -eq "$API" ]; then
  if [ "$API" -ge "17" ]; then
    SUGOTE=true
    PIE=.pie
    if [ "$ARCH" = "x86" ]; then SU=su.pie; fi;
    if [ "$ABILONG" = "armeabi-v7a" ]; then ARCH=armv7; fi;
    if [ "$ABI" = "mip" ]; then ARCH=mips; fi;
    if [ "$ABILONG" = "mips" ]; then ARCH=mips; fi;
  fi
  if [ "$API" -ge "18" ]; then
    SUMOD=0755
  fi
  if [ "$API" -ge "20" ]; then
    if [ "$ABILONG" = "arm64-v8a" ]; then ARCH=arm64; SYSTEMLIB=/system/lib64; APPPROCESS64=true; fi;
    if [ "$ABILONG" = "mips64" ]; then ARCH=mips64; SYSTEMLIB=/system/lib64; APPPROCESS64=true; fi;
    if [ "$ABILONG" = "x86_64" ]; then ARCH=x64; SYSTEMLIB=/system/lib64; APPPROCESS64=true; fi;
    APKFOLDER=true
    APKNAME=/system/app/SuperSU/SuperSU.apk
  fi
  if [ "$API" -ge "19" ]; then
    SUPOLICY=true
    if [ "$(LD_LIBRARY_PATH=$SYSTEMLIB /system/toolbox ls -lZ /system/bin/toolbox | grep toolbox_exec > /dev/null; echo $?)" -eq "0" ]; then
      INSTALL_RECOVERY_CONTEXT=u:object_r:toolbox_exec:s0
    fi
  fi
  if [ "$API" -ge "21" ]; then
    APPPROCESS=true
  fi
  if [ "$API" -ge "22" ]; then
    SUGOTE=false
  fi
fi
if [ ! -f $MKSH ]; then
  MKSH=/system/bin/sh
fi

#ui_print "DBG [$API] [$ABI] [$ABI2] [$ABILONG] [$ARCH] [$MKSH]"

if [ -z "$BIN" ]; then
  ui_print "- Extracting files"

  cd /tmp
  mkdir supersu
  cd supersu

  unzip -o "$ZIP"

  BIN=/tmp/supersu/$ARCH
  COM=/tmp/supersu/common
fi

# execute binaries from ramdisk
chmod -R 0755 $BIN/*
RAMDISKLIB=$BIN:$SYSTEMLIB

if [ "$API" -ge "19" ]; then
  # 4.4+: permissive all teh things
  LD_LIBRARY_PATH=$RAMDISKLIB $BIN/supolicy --live "permissive *"
fi

SAMSUNG=false
if [ "$API" -eq "$API" ]; then
  SAMSUNG_CHECK=$(cat /system/build.prop | grep "ro.build.fingerprint=" | grep -i "samsung")
  if [ $? -eq 0 ]; then
    SAMSUNG=true
  fi

  if [ "$API" -ge "23" ]; then
    # 6.0+
    ui_print "- Detecting system compatibility"
    detect_systemless_required

    if ($SYSTEMLESS); then
      RWSYSTEM=false
    fi
  elif [ "$API" -ge "21" ]; then
    # 5.1/Samsung
    # On 5.0, auto-detect sets systemless only for 5.1/Samsung
    # But we allow SYSTEMLESS=true override for 3rd party mods
    # - that doesn't officially work, though!
    if [ "$SYSTEMLESS" = "detect" ]; then
      SYSTEMLESS=false
      if [ "$API" -ge "22" ]; then
        if ($SAMSUNG); then
          SYSTEMLESS=true
        fi
      fi
    fi

    if ($SYSTEMLESS); then
      RWSYSTEM=false
    fi
  fi
fi

# Do not use SYSTEMLESS after this point, but refer to RWSYSTEM

if ($RWSYSTEM); then
  ui_print "- System mode"

  remount_system_rw

  ui_print "- Disabling OTA survival"
  chmod 0755 $BIN/chattr$PIE
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/bin/su
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/xbin/su
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/bin/.ext/.su
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/sbin/su
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /vendor/sbin/su
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /vendor/bin/su
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /vendor/xbin/su
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/xbin/daemonsu
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/xbin/sugote
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/xbin/sugote_mksh
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/xbin/supolicy
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/xbin/ku.sud
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/xbin/.ku
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/xbin/.su
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/lib/libsupol.so
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/lib64/libsupol.so
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/etc/install-recovery.sh
  LD_LIBRARY_PATH=$SYSTEMLIB $BIN/chattr$PIE -ia /system/bin/install-recovery.sh

  ui_print "- Removing old files"

  if [ -f "/system/bin/install-recovery.sh" ]; then
    if [ ! -f "/system/bin/install-recovery_original.sh" ]; then
      mv /system/bin/install-recovery.sh /system/bin/install-recovery_original.sh
      ch_con /system/bin/install-recovery_original.sh
    fi
  fi
  if [ -f "/system/etc/install-recovery.sh" ]; then
    if [ ! -f "/system/etc/install-recovery_original.sh" ]; then
      mv /system/etc/install-recovery.sh /system/etc/install-recovery_original.sh
      ch_con /system/etc/install-recovery_original.sh
    fi
  fi

  # only wipe these files in /system install, so not part of the wipe_ functions

  rm -f /system/bin/install-recovery.sh
  rm -f /system/etc/install-recovery.sh

  rm -f /system/bin/su
  rm -f /system/xbin/su
  rm -f /system/sbin/su
  rm -f /vendor/sbin/su
  rm -f /vendor/bin/su
  rm -f /vendor/xbin/su

  rm -rf /data/app/eu.chainfire.supersu-*
  rm -rf /data/app/eu.chainfire.supersu.apk

  wipe_system_files_if_present
  wipe_data_competitors_and_cache

  rm /data/su.img
  rm /cache/su.img

  ui_print "- Creating space"
  if ($APKFOLDER); then
    if [ -f "/system/app/Maps/Maps.apk" ]; then
      cp /system/app/Maps/Maps.apk /Maps.apk
      rm /system/app/Maps/Maps.apk
    fi
    if [ -f "/system/app/GMS_Maps/GMS_Maps.apk" ]; then
      cp /system/app/GMS_Maps/GMS_Maps.apk /GMS_Maps.apk
      rm /system/app/GMS_Maps/GMS_Maps.apk
    fi
    if [ -f "/system/app/YouTube/YouTube.apk" ]; then
      cp /system/app/YouTube/YouTube.apk /YouTube.apk
      rm /system/app/YouTube/YouTube.apk
    fi
  else
    if [ -f "/system/app/Maps.apk" ]; then
      cp /system/app/Maps.apk /Maps.apk
      rm /system/app/Maps.apk
    fi
    if [ -f "/system/app/GMS_Maps.apk" ]; then
      cp /system/app/GMS_Maps.apk /GMS_Maps.apk
      rm /system/app/GMS_Maps.apk
    fi
    if [ -f "/system/app/YouTube.apk" ]; then
      cp /system/app/YouTube.apk /YouTube.apk
      rm /system/app/YouTube.apk
    fi
  fi

  ui_print "- Placing files"

  mkdir /system/bin/.ext
  set_perm 0 0 0777 /system/bin/.ext
  cp_perm 0 0 $SUMOD $BIN/$SU /system/bin/.ext/.su
  cp_perm 0 0 $SUMOD $BIN/$SU /system/xbin/su
  cp_perm 0 0 0755 $BIN/$SU /system/xbin/daemonsu
  if ($SUGOTE); then
    cp_perm 0 0 0755 $BIN/$SU /system/xbin/sugote u:object_r:zygote_exec:s0
    cp_perm 0 0 0755 $MKSH /system/xbin/sugote-mksh
  fi
  if ($SUPOLICY); then
    cp_perm 0 0 0755 $BIN/supolicy /system/xbin/supolicy
    cp_perm 0 0 0644 $BIN/libsupol.so $SYSTEMLIB/libsupol.so
  fi
  if ($APKFOLDER); then
    mkdir /system/app/SuperSU
    set_perm 0 0 0755 /system/app/SuperSU
  fi
  cp_perm 0 0 0644 $COM/Superuser.apk $APKNAME
  cp_perm 0 0 0755 $COM/install-recovery.sh /system/etc/install-recovery.sh
  ln_con /system/etc/install-recovery.sh /system/bin/install-recovery.sh
  if ($APPPROCESS); then
    rm /system/bin/app_process
    ln_con /system/xbin/daemonsu /system/bin/app_process
    if ($APPPROCESS64); then
      if [ ! -f "/system/bin/app_process64_original" ]; then
        mv /system/bin/app_process64 /system/bin/app_process64_original
      else
        rm /system/bin/app_process64
      fi
      ln_con /system/xbin/daemonsu /system/bin/app_process64
      if [ ! -f "/system/bin/app_process_init" ]; then
        cp_perm 0 2000 0755 /system/bin/app_process64_original /system/bin/app_process_init
      fi
    else
      if [ ! -f "/system/bin/app_process32_original" ]; then
        mv /system/bin/app_process32 /system/bin/app_process32_original
      else
        rm /system/bin/app_process32
      fi
      ln_con /system/xbin/daemonsu /system/bin/app_process32
      if [ ! -f "/system/bin/app_process_init" ]; then
        cp_perm 0 2000 0755 /system/bin/app_process32_original /system/bin/app_process_init
      fi
    fi
  fi
  cp_perm 0 0 0744 $COM/99SuperSUDaemon /system/etc/init.d/99SuperSUDaemon
  echo 1 > /system/etc/.installed_su_daemon
  set_perm 0 0 0644 /system/etc/.installed_su_daemon

  ui_print "- Restoring files"
  if ($APKFOLDER); then
    if [ -f "/Maps.apk" ]; then
      cp_perm 0 0 0644 /Maps.apk /system/app/Maps/Maps.apk
      rm /Maps.apk
    fi
    if [ -f "/GMS_Maps.apk" ]; then
      cp_perm 0 0 0644 /GMS_Maps.apk /system/app/GMS_Maps/GMS_Maps.apk
      rm /GMS_Maps.apk
    fi
    if [ -f "/YouTube.apk" ]; then
      cp_perm 0 0 0644 /YouTube.apk /system/app/YouTube/YouTube.apk
      rm /YouTube.apk
    fi
  else
    if [ -f "/Maps.apk" ]; then
      cp_perm 0 0 0644 /Maps.apk /system/app/Maps.apk
      rm /Maps.apk
    fi
    if [ -f "/GMS_Maps.apk" ]; then
      cp_perm 0 0 0644 /GMS_Maps.apk /system/app/GMS_Maps.apk
      rm /GMS_Maps.apk
    fi
    if [ -f "/YouTube.apk" ]; then
      cp_perm 0 0 0644 /YouTube.apk /system/app/YouTube.apk
      rm /YouTube.apk
    fi
  fi

  ui_print "- Post-installation script"
  rm /system/toybox
  rm /system/toolbox
  LD_LIBRARY_PATH=$SYSTEMLIB /system/xbin/su --install
else
  ui_print "- System-less mode, boot image support required"

  SUIMG=/data/su.img
  HAVEDATA=true
  if (! is_mounted /data); then
    SUIMG=/cache/su.img
    HAVEDATA=false
  fi

  ui_print "- Creating image"

  # we want a 96M image, for SuperSU files and potential mods such as systemless xposed
  # attempt smaller sizes on failure, and hope the launch_daemonsu.sh script succeeds
  # in resizing to 96M later
  for SUIMGSIZE in 96M 64M 32M 16M; do
    if [ ! -f "$SUIMG" ]; then make_ext4fs -l $SUIMGSIZE -a /su -S $COM/file_contexts_image $SUIMG; fi
    if [ ! -f "$SUIMG" ]; then LD_LIBRARY_PATH=$SYSTEMLIB /system/bin/make_ext4fs -l $SUIMGSIZE -a /su -S $COM/file_contexts_image $SUIMG; fi
    set_perm 0 0 0600 /data/su.img u:object_r:system_data_file:s0
  done

  if [ -f "$SUIMG" ]; then
    LD_LIBRARY_PATH=$SYSTEMLIB /system/bin/e2fsck -p -f $SUIMG
  fi

  ui_print "- Mounting image"

  mkdir /su

  # 'losetup -f' is unreliable across devices/recoveries
  LOOPDEVICE=
  for LOOP in 0 1 2 3 4 5 6 7; do
    if (! is_mounted /su); then
      LOOPDEVICE=/dev/block/loop$LOOP
      HAVE_LOOPDEVICE=false
      if [ -f "$LOOPDEVICE" ]; then
        HAVE_LOOPDEVICE=true
      elif [ -b "$LOOPDEVICE" ]; then
        HAVE_LOOPDEVICE=true;
      fi
      if (! $HAVE_LOOPDEVICE); then
        mknod $LOOPDEVICE b 7 $LOOP
      fi
      losetup $LOOPDEVICE $SUIMG
      if [ "$?" -eq "0" ]; then
        mount -t ext4 -o loop $LOOPDEVICE /su
        if (! is_mounted /su); then
          /system/bin/toolbox mount -t ext4 -o loop $LOOPDEVICE /su
        fi
        if (! is_mounted /su); then
          /system/bin/toybox mount -t ext4 -o loop $LOOPDEVICE /su
        fi
      fi
      if (is_mounted /su); then
        break;
      fi
    fi
  done

  ui_print "- Creating paths"

  mkdir /su/bin
  set_perm 0 0 0751 /su/bin
  mkdir /su/xbin
  set_perm 0 0 0755 /su/xbin
  mkdir /su/lib
  set_perm 0 0 0755 /su/lib
  mkdir /su/etc
  set_perm 0 0 0755 /su/etc
  mkdir /su/su.d
  set_perm 0 0 0700 /su/su.d

  ui_print "- Removing old files"

  wipe_system_files_if_present
  wipe_data_competitors_and_cache

  rm -rf /su/bin/app_process
  rm -rf /su/bin/sush
  rm -rf /su/bin/daemonsu
  rm -rf /su/bin/daemonsu_*
  rm -rf /su/bin/su
  rm -rf /su/bin/su_*
  rm -rf /su/bin/supolicy
  rm -rf /su/bin/supolicy_*
  rm -rf /su/lib/libsupol.so
  rm -rf /su/lib/libsupol_*
  rm -rf /su/bin/sukernel

  ui_print "- Placing files"

  # Copy binaries and utilities
  cp_perm 0 0 0755 $BIN/$SU /su/bin/su
  cp_perm 0 0 0755 $BIN/$SU /su/bin/daemonsu
  ln_con /su/bin/su /su/bin/supolicy
  cp_perm 0 0 0755 $BIN/supolicy /su/bin/supolicy_wrapped
  cp_perm 0 0 0644 $BIN/libsupol.so /su/lib/libsupol.so
  cp_perm 0 0 0755 $BIN/sukernel /su/bin/sukernel

  # Copy APK, installation is done by /sbin/launch_daemonsu.sh
  if ($HAVEDATA); then
    cp_perm 1000 1000 0600 $COM/Superuser.apk /data/SuperSU.apk

    # Wipe /data/security to prevent SELinux policy override
    # Important to keep the folder itself
    rm -rf /data/security/*
  else
    cp_perm 1000 1000 0600 $COM/Superuser.apk /cache/SuperSU.apk
  fi

  # Fix Samsung deep sleep issue. Affects enough millions of users to include.
  if ($SAMSUNG); then
    cp_perm 0 0 0700 $COM/000000deepsleep /su/su.d/000000deepsleep
  fi

  if ($BINDSYSTEMXBIN); then
    mkdir /su/xbin_bind
    set_perm 0 0 0755 /su/xbin_bind
  else
    rm -rf /su/xbin_bind
  fi

  if ($PATCHBOOTIMAGE); then
    ui_print " "
    ui_print        "******************"
    ui_print_always "Boot image patcher"
    ui_print        "******************"

    ui_print "- Finding boot image"
    find_boot_image

    CONTINUE=true
    if [ -z "$BOOTIMAGE" ]; then
      ui_print_less "$UI_PRINT_LAST"
      ui_print_always "--- Boot image: not found, aborting"
      CONTINUE=false
    else
      ui_print "--- Boot image: $BOOTIMAGE"
    fi

    if [ -z "$STOCKBOOTIMAGE" ]; then
      STOCKBOOTIMAGE=$BOOTIMAGE
    fi

    rm -rf /sutmp
    mkdir /sutmp

    IMAGETYPE=android
    LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --bootimg-type $BOOTIMAGE
    if [ $? -eq 2 ]; then
      IMAGETYPE=chromeos
    fi

    check_zero_def "- Extracting ramdisk" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --bootimg-extract-ramdisk $BOOTIMAGE /sutmp/ramdisk.packed"
    check_zero_def "- Decompressing ramdisk" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --ungzip /sutmp/ramdisk.packed /sutmp/ramdisk"

    if ($CONTINUE); then
      ui_print "- Checking patch status"
      LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --patch-test /sutmp/ramdisk
      if [ $? -ne 0 ]; then
        ui_print "--- Already patched, attempting to find stock backup"

        if ($CONTINUE); then
          LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --restore /sutmp/ramdisk /sutmp/stock_boot.img
          if [ $? -ne 0 ]; then
            ui_print_always "--- Stock restore failed, attempting ramdisk restore"
            CONTINUE=false
          else
            ui_print "--- Stock backup restored"
            STOCKBOOTIMAGE=/sutmp/stock_boot.img
          fi
        fi

        check_zero_def "- Extracting ramdisk" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --bootimg-extract-ramdisk /sutmp/stock_boot.img /sutmp/ramdisk.packed"
        check_zero_def "- Decompressing ramdisk" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --ungzip /sutmp/ramdisk.packed /sutmp/ramdisk"
        check_zero "- Checking patch status" "" "--- Already patched, attempting ramdisk restore" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --patch-test /sutmp/ramdisk"

        if (! $CONTINUE); then
          LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-restore /sutmp/ramdisk /sutmp/ramdisk
          if [ $? -ne 0 ]; then
            ui_print_always "--- Ramdisk restore failed, aborting"
          else
            ui_print "--- Ramdisk backup restored (OTA impossible)"
            CONTINUE=true
          fi
          check_zero "- Checking patch status" "" "--- Already patched, aborting" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --patch-test /sutmp/ramdisk"
        fi
      else
        ui_print "- Creating backup"
        rm /data/stock_boot_*.img
        rm /data/stock_boot_*.img.gz
        rm /cache/stock_boot_*.img
        rm /cache/stock_boot_*.img.gz
        LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --backup $BOOTIMAGE
        if [ $? -ne 0 ]; then
          ui_print "--- Backup failed"
        fi
      fi
    fi

    if ($CONTINUE); then
      cp_perm 0 0 0644 /sutmp/ramdisk /sutmp/ramdisk.original

      if ($SLOT_USED); then
        check_zero_def "- Importing system_root" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-import-system-root /sutmp/ramdisk /sutmp/ramdisk"
      fi
    fi

    if ($CONTINUE); then
      ui_print "- Patching sepolicy"

      check_zero_def "" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-extract /sutmp/ramdisk ${CPIO_PREFIX}sepolicy /sutmp/sepolicy"

      if ($CONTINUE); then
        if ($PERMISSIVE); then
          LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/supolicy --file /sutmp/sepolicy /sutmp/sepolicy.patched "permissive *"
        else
          LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/supolicy --file /sutmp/sepolicy /sutmp/sepolicy.patched
        fi
        if [ ! -f "/sutmp/sepolicy.patched" ]; then
          ui_print_less "$UI_PRINT_LAST"
          ui_print_always "--- Failure, aborting"
          CONTINUE=false
        fi
      fi

      check_zero_def "" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-add /sutmp/ramdisk /sutmp/ramdisk 644 ${CPIO_PREFIX}sepolicy /sutmp/sepolicy.patched"
    fi

    check_zero_def "- Adding daemon launcher" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-add /sutmp/ramdisk /sutmp/ramdisk 700 ${CPIO_PREFIX}sbin/launch_daemonsu.sh $COM/launch_daemonsu.sh"
    check_zero_def "- Adding init script" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-add /sutmp/ramdisk /sutmp/ramdisk 750 ${CPIO_PREFIX}init.supersu.rc $COM/init.supersu.rc"

    check_zero_def "- Creating mount point" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-mkdir /sutmp/ramdisk /sutmp/ramdisk 755 ${CPIO_PREFIX}su"

    COMMAND="LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --patch /sutmp/ramdisk /sutmp/ramdisk $STOCKBOOTIMAGE --sdk=$API"
    if ($KEEPVERITY); then
      COMMAND="$COMMAND --keep-verity"
    fi
    if ($KEEPFORCEENCRYPT); then
      COMMAND="$COMMAND --keep-forceencrypt"
    fi
    check_zero_def "- Patching init.*.rc, fstabs, file_contexts, dm-verity" "$COMMAND"

    if ($CONTINUE); then
      if ($SLOT_USED); then
        ui_print "- Patching init, system_root, system"

        LD_LIBRARY_PATH=$RAMDISKLIB $BIN/sukernel --cpio-extract /sutmp/ramdisk sbin/twrp /sutmp/twrp
        if [ -f "/sutmp/twrp" ]; then
            # backup TWRP's version of init
            check_zero_def "" "LD_LIBRARY_PATH=$RAMDISKLIB $BIN/sukernel --cpio-extract /sutmp/ramdisk init /sutmp/init_twrp"
            check_zero_def "" "LD_LIBRARY_PATH=$RAMDISKLIB $BIN/sukernel --cpio-add /sutmp/ramdisk /sutmp/ramdisk 750 init_twrp /sutmp/init_twrp"
        fi

        check_zero_def "" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-add /sutmp/ramdisk /sutmp/ramdisk 750 init $BIN/suinit"
        check_zero_def "" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-mkdir /sutmp/ramdisk /sutmp/ramdisk 755 boot/system_root"
        check_zero_def "" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-mkdir /sutmp/ramdisk /sutmp/ramdisk 755 boot/system"

        if (! $CONTINUE); then
          ui_print_less "$UI_PRINT_LAST"
          ui_print_always "--- Failure, aborting"
        fi
      fi
    fi

    if [ -f "/data/custom_ramdisk_patch.sh" ]; then
      check_zero_def "- Calling user ramdisk patch script" "sh /data/custom_ramdisk_patch.sh /sutmp/ramdisk"
    fi

    if ($CONTINUE); then
      if ($FRP); then
        ui_print "- Factory reset protection"
        check_zero_def "" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-mkdir /sutmp/ramdisk /sutmp/ramdisk 0 ${CPIO_PREFIX}.sufrp"
        check_zero_def "" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-add /sutmp/ramdisk /sutmp/ramdisk 755 ${CPIO_PREFIX}.sufrp/frp_install $COM/frp_install"
        check_zero_def "" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-add /sutmp/ramdisk /sutmp/ramdisk 644 ${CPIO_PREFIX}.sufrp/file_contexts_image $COM/file_contexts_image"
        check_zero_def "" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-add /sutmp/ramdisk /sutmp/ramdisk 644 ${CPIO_PREFIX}.sufrp/su $BIN/su"
        check_zero_def "" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-add /sutmp/ramdisk /sutmp/ramdisk 644 ${CPIO_PREFIX}.sufrp/sukernel $BIN/sukernel"
        check_zero_def "" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-add /sutmp/ramdisk /sutmp/ramdisk 644 ${CPIO_PREFIX}.sufrp/supolicy $BIN/supolicy"
        check_zero_def "" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-add /sutmp/ramdisk /sutmp/ramdisk 644 ${CPIO_PREFIX}.sufrp/libsupol.so $BIN/libsupol.so"
      fi
    fi

    check_zero_def "- Creating ramdisk backup" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --cpio-backup /sutmp/ramdisk.original /sutmp/ramdisk /sutmp/ramdisk"

    check_zero_def "- Compressing ramdisk" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --gzip /sutmp/ramdisk /sutmp/ramdisk.packed"

    if [ "$IMAGETYPE" = "chromeos" ]; then
      $BIN/chromeos/futility vbutil_kernel --get-vmlinuz $STOCKBOOTIMAGE --vmlinuz-out /sutmp/boot.chromeos.img
      STOCKBOOTIMAGE=/sutmp/boot.chromeos.img
    fi

    check_zero_def "- Creating boot image" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --bootimg-replace-ramdisk $STOCKBOOTIMAGE /sutmp/ramdisk.packed /sutmp/boot.img"

    if ($SLOT_USED); then
      check_zero_def "- Extracting kernel" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --bootimg-extract-kernel $BOOTIMAGE /sutmp/kernel"

      KERNEL_COMPRESSED=false
      if ($CONTINUE); then
        ui_print "- Decompressing kernel"
        if (`LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --ungzip /sutmp/kernel /sutmp/kernel >/dev/null 2>/dev/null`); then
          KERNEL_COMPRESSED=true
        fi
      fi

      check_zero_def "- Patching kernel" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --patch-slot-kernel /sutmp/kernel /sutmp/kernel"

      if ($CONTINUE); then
        if ($KERNEL_COMPRESSED); then
          check_zero_def "- Compressing kernel" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --gzip /sutmp/kernel /sutmp/kernel"
        fi
      fi

      if ($CONTINUE); then
        check_zero_def "- Replacing kernel" "LD_LIBRARY_PATH=$SYSTEMLIB /su/bin/sukernel --bootimg-replace-kernel /sutmp/boot.img /sutmp/kernel /sutmp/boot.img"
      fi
    fi

    if [ "$IMAGETYPE" = "chromeos" ]; then
      ui_print "- Signing boot image"
      $BIN/chromeos/futility vbutil_kernel --pack /sutmp/boot.img.signed --keyblock $COM/chromeos/kernel.keyblock --signprivate $COM/chromeos/kernel_data_key.vbprivk --version 1 --vmlinuz /sutmp/boot.img --config $COM/chromeos/kernel.config --arch arm --bootloader $COM/chromeos/kernel.bootloader --flags 0x1
      if [ -f "/sutmp/boot.img.signed" ]; then
        rm -rf /sutmp/boot.img
        mv /sutmp/boot.img.signed /sutmp/boot.img
      else
        ui_print_less "$UI_PRINT_LAST"
        ui_print_always "--- Failure, aborting"
        $CONTINUE=false
      fi
    fi

    if ($CONTINUE); then
        # might return 1 even if we do not want to abort
        ui_print "- Applying hex patches"
        /su/bin/sukernel --hexpatch $COM/hexpatch /sutmp/boot.img /sutmp/boot.img
    fi

    if [ -f "/data/custom_boot_image_patch.sh" ]; then
        check_zero_def "- Calling user boot image patch script" "sh /data/custom_boot_image_patch.sh /sutmp/boot.img"
    fi

    if ($CONTINUE); then
      DEV=$(echo `resolve_link $BOOTIMAGE` | grep /dev/block/)
      if [ $? -eq 0 ]; then
        ui_print "- Flashing boot image"
        dd if=/dev/zero of=$BOOTIMAGE bs=4096
      else
        ui_print "- Saving boot image"
      fi

      if ($SAMSUNG); then
        # Prevent "KERNEL IS NOT SEANDROID ENFORCING"
        SAMSUNG_CHECK=$(cat /sutmp/boot.img | grep SEANDROIDENFORCE)
        if [ $? -ne 0 ]; then
          echo -n "SEANDROIDENFORCE" >> /sutmp/boot.img
        fi
      fi

      dd if=/sutmp/boot.img of=$BOOTIMAGE bs=4096
    fi

    rm -rf /sutmp
  fi

  umount /su
  losetup -d $LOOPDEVICE

  ui_print " "
  ui_print "*************************"
  ui_print "    IMPORTANT NOTICES    "
  ui_print "*************************"

  TWRP2=$(cat /tmp/recovery.log | grep "ro.twrp.version=2");
  if [ $? -eq 0 ]; then
    ui_print "If TWRP offers to install"
    ui_print "SuperSU, do *NOT* let it!"
    ui_print "*************************"
  fi

  ui_print "First reboot may take a  "
  ui_print "few minutes. It can also "
  ui_print "loop a few times. Do not "
  ui_print "interrupt the process!   "
  ui_print "*************************"
  ui_print " "

  if (! $LESSLOGGING); then
    sleep 5
  fi
fi

ui_print "- Unmounting /system"
if ($SLOT_USED); then
  if (! $HAD_SYSTEM_ROOT); then
    umount /system
    umount /system_root
    if ($HAD_SYSTEM); then
      if ($HAD_SYSTEM_RW); then
        mount -o rw /system
      else
        mount -o ro /system
      fi
    fi
  fi
else
  if (! $HAD_SYSTEM); then
    umount /system
  fi
fi

ui_print_always "- Done !"
exit 0
