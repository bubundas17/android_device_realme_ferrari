#
# Copyright (C) 2021-2025 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# AAPT
PRODUCT_AAPT_CONFIG := normal
PRODUCT_AAPT_PREF_CONFIG := xxxhdpi

# Audio
# AGM loads /vendor/etc/acdbdata/<sndcard>. The camera-blob regen dropped
# the waipio_mtp copies; without them AudioService blocks and bootanim never exits.
PRODUCT_COPY_FILES += \
    vendor/realme/ferrari/proprietary/odm/etc/acdbdata/acdb_cal.acdb:$(TARGET_COPY_OUT_VENDOR)/etc/acdbdata/waipio_mtp/MTP_acdb_cal.acdb \
    vendor/realme/ferrari/proprietary/odm/etc/acdbdata/FTM/workspaceFileXml.qwsp:$(TARGET_COPY_OUT_VENDOR)/etc/acdbdata/waipio_mtp/MTP_workspaceFileXml.qwsp

PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/audio/backend_conf.xml:$(TARGET_COPY_OUT_ODM)/etc/backend_conf.xml \
    $(LOCAL_PATH)/audio/mixer_paths_waipio_mtp.xml:$(TARGET_COPY_OUT_ODM)/etc/mixer_paths.xml \
    $(LOCAL_PATH)/audio/mixer_paths_waipio_mtp.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio/sku_taro/mixer_paths_waipio_mtp.xml \
    $(LOCAL_PATH)/audio/resourcemanager_waipio_mtp.xml:$(TARGET_COPY_OUT_ODM)/etc/resourcemanager.xml \
    $(LOCAL_PATH)/audio/resourcemanager_waipio_mtp.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio/sku_taro/resourcemanager_waipio_mtp.xml \
    $(LOCAL_PATH)/audio/sound_trigger_mixer_paths.xml:$(TARGET_COPY_OUT_ODM)/etc/sound_trigger_mixer_paths.xml \
    $(LOCAL_PATH)/audio/sound_trigger_mixer_paths.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio/sku_taro/sound_trigger_mixer_paths.xml \
    $(LOCAL_PATH)/audio/sound_trigger_platform_info.xml:$(TARGET_COPY_OUT_ODM)/etc/sound_trigger_platform_info.xml \
    $(LOCAL_PATH)/audio/sound_trigger_platform_info.xml:$(TARGET_COPY_OUT_VENDOR)/etc/audio/sku_taro/sound_trigger_platform_info.xml \
    $(LOCAL_PATH)/audio/usecaseKvManager.xml:$(TARGET_COPY_OUT_ODM)/etc/usecaseKvManager.xml \
    $(LOCAL_PATH)/audio/usecaseKvManager.xml:$(TARGET_COPY_OUT_VENDOR)/etc/usecaseKvManager.xml

# Boot animation
TARGET_SCREEN_HEIGHT := 3216
TARGET_SCREEN_WIDTH := 1440

# Display
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/display/displayconfig.xml:$(TARGET_COPY_OUT_VENDOR)/etc/displayconfig/display_id_4630946358012694401.xml

$(call soong_config_set_bool,qtidisplay,oplus_udfps,true)
$(call soong_config_set,qtidisplay,pxlw_vendor_namespace,vendor/oneplus/sm8450-common)

# Fingerprint
PRODUCT_PACKAGES += \
    android.hardware.biometrics.fingerprint@2.3-service.oplus

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.fingerprint.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.fingerprint.xml

$(call soong_config_set,surfaceflinger,udfps_lib,//hardware/oplus:libudfps_extension.oplus)

# NFC
PRODUCT_PACKAGES += \
    android.hardware.nfc-service.nxp \
    com.android.nfc_extras \
    Tag

PRODUCT_COPY_FILES += \
    frameworks/native/data/etc/android.hardware.nfc.ese.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.ese.xml \
    frameworks/native/data/etc/android.hardware.nfc.hce.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.hce.xml \
    frameworks/native/data/etc/android.hardware.nfc.hcef.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.hcef.xml \
    frameworks/native/data/etc/android.hardware.nfc.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.nfc.xml \
    frameworks/native/data/etc/android.hardware.se.omapi.ese.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.se.omapi.ese.xml \
    frameworks/native/data/etc/android.hardware.se.omapi.uicc.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/android.hardware.se.omapi.uicc.xml \
    frameworks/native/data/etc/com.android.nfc_extras.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/com.android.nfc_extras.xml \
    frameworks/native/data/etc/com.nxp.mifare.xml:$(TARGET_COPY_OUT_VENDOR)/etc/permissions/com.nxp.mifare.xml

# Overlays
DEVICE_PACKAGE_OVERLAYS += \
    $(LOCAL_PATH)/overlay-lineage

PRODUCT_PACKAGES += \
    OPlusFrameworksResTarget \
    OPlusSettingsProviderResTarget \
    OPlusSettingsResTarget \
    OPlusSystemUIResTarget

# Soong namespaces
PRODUCT_SOONG_NAMESPACES += \
    $(LOCAL_PATH)

# Inherit from the common OEM chipset makefile.
$(call inherit-product, device/oneplus/sm8450-common/common.mk)

# Inherit from the proprietary files makefile.
$(call inherit-product, vendor/realme/ferrari/ferrari-vendor.mk)

# Stock OPlusCamera integration
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/camera/media_profiles_vendor.xml:$(TARGET_COPY_OUT_VENDOR)/etc/media_profiles_vendor.xml \
    $(LOCAL_PATH)/configs/camera/oplus_camera_default_grant_permissions_list.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/default-permissions/oplus_camera_default_grant_permissions_list.xml \
    $(LOCAL_PATH)/configs/camera/oplus_google_lens_config.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/oplus_google_lens_config.xml \
    $(LOCAL_PATH)/configs/camera/privapp-permissions-oplus-camera.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/permissions/privapp-permissions-oplus-camera.xml \
    $(LOCAL_PATH)/configs/camera/initial-package-stopped-states-oplus-camera.xml:$(TARGET_COPY_OUT_SYSTEM_EXT)/etc/sysconfig/initial-package-stopped-states-oplus-camera.xml \
    $(LOCAL_PATH)/configs/camera/hiddenapi-package-oplus-camera-whitelist.xml:$(TARGET_COPY_OUT_SYSTEM)/etc/sysconfig/hiddenapi-package-oplus-camera-whitelist.xml

PRODUCT_BOOT_JARS += \
    oplus-support-wrapper

PRODUCT_PRODUCT_PROPERTIES += \
    persist.vendor.camera.privapp.list=com.oplus.camera \
    ro.com.google.lens.oem_camera_package=com.oplus.camera

PRODUCT_SYSTEM_EXT_PROPERTIES += \
    media.settings.xml=/vendor/etc/media_profiles_vendor.xml

PRODUCT_PACKAGES += \
    init.oplus.camera.rc \
    init.ferrari.perf.rc

# Compressed RAM swap (ZRAM). Module is present in vendor_dlkm but not loaded
# by default; init.ferrari.perf.rc modprobes it and swapon_all this fstab.
PRODUCT_COPY_FILES += \
    $(LOCAL_PATH)/configs/fstab.zram:$(TARGET_COPY_OUT_VENDOR)/etc/fstab.zram

# user builds: QTI USB init clears persist.vendor.usb.config and expects
# persist.sys.usb.config to drive the gadget. Default to MTP so the phone
# enumerates and shows the USB notification (adb-only defaults break when
# USB debugging is off).
ifeq ($(TARGET_BUILD_VARIANT),user)
PRODUCT_SYSTEM_DEFAULT_PROPERTIES += \
    persist.sys.usb.config=mtp
endif

# Pass the calling package through the OPLUS vendor tag and preserve the
# reserved pixel format used by the stock camera HAL.
$(call soong_config_set,camera,package_name,com.oplus.packageName)
$(call soong_config_set_bool,camera,override_format_from_reserved,true)

# Let the camera service link the ferrari torch strength extension lib
# (LibreMobileOS weak-symbol hook in libcameraservice).
$(call soong_config_set,libcameraservice,ext_lib,libferrari_torch_ext)
