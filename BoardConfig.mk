#
# Copyright (C) 2021-2023 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Include the common OEM chipset BoardConfig.
include device/oneplus/sm8450-common/BoardConfigCommon.mk

DEVICE_PATH := device/realme/ferrari

# HIDL
DEVICE_MANIFEST_FILE += $(DEVICE_PATH)/manifest.xml

# Properties
TARGET_VENDOR_PROP += $(DEVICE_PATH)/vendor.prop

# Recovery
TARGET_RECOVERY_DENSITY := xxhdpi
TARGET_RECOVERY_UI_MARGIN_HEIGHT := 126

# Include the proprietary files BoardConfig.
include vendor/realme/ferrari/BoardConfigVendor.mk

# SEPolicy
BOARD_VENDOR_SEPOLICY_DIRS += \
    $(DEVICE_PATH)/sepolicy/vendor

SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += \
    $(DEVICE_PATH)/sepolicy/private

SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS += \
    $(DEVICE_PATH)/sepolicy/public

# pixel-style's com.google.android.webapp uses prefer+overrides to steal the
# bootclasspath WebApp apex from AOSP. The last booting 12.0 image shipped
# com.android.webapp.capex; keep that on ferrari.
SOONG_CONFIG_NAMESPACES += evo_ferrari
SOONG_CONFIG_evo_ferrari += disable_google_webapp
SOONG_CONFIG_evo_ferrari_disable_google_webapp := true
$(call soong_config_set_bool,evo_ferrari,disable_google_webapp,true)
