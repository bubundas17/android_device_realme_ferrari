#
# Copyright (C) 2021-2024 The LineageOS Project
#
# SPDX-License-Identifier: Apache-2.0
#

# Inherit from those products. Most specific first.
$(call inherit-product, $(SRC_TARGET_DIR)/product/core_64_bit_only.mk)
$(call inherit-product, $(SRC_TARGET_DIR)/product/full_base_telephony.mk)

# Inherit from ferrari device
$(call inherit-product, device/realme/ferrari/device.mk)

# Inherit Evolution X common config
$(call inherit-product, vendor/lineage/config/common_full_phone.mk)

# Drop packages that break ferrari bring-up after the Evolution-X 12.1 sync.
# Google WebApp is also disabled in Soong (BoardConfig evo_ferrari) because
# prefer+overrides still installs it when only PRODUCT_PACKAGES is filtered.
PRODUCT_PACKAGES := $(filter-out \
    SystemUIClocks-Flex \
    com.google.android.webapp \
    LMOFreeform \
    LMOFreeformSidebar \
    ,$(PRODUCT_PACKAGES))

PRODUCT_NAME := evolution_ferrari
PRODUCT_DEVICE := ferrari
PRODUCT_MANUFACTURER := realme
PRODUCT_BRAND := realme
PRODUCT_MODEL := RMX3301

# Authorize the developer's Linux/WSL and Windows ADB public keys on this
# userdebug build. Only public keys are included; private keys stay on hosts.
PRODUCT_ADB_KEYS := $(LOCAL_PATH)/adb_keys

PRODUCT_GMS_CLIENTID_BASE := android-oppo

PRODUCT_BUILD_PROP_OVERRIDES += \
    BuildDesc="RMX3301-user 15 AP3A.240617.008 S.1e1fd2e-39b2-5cafa release-keys" \
    BuildFingerprint=realme/RMX3301/RED8ACL1:15/AP3A.240617.008/S.1e1fd2e-39b2-5cafa:user/release-keys \
    DeviceName=RED8ACL1 \
    DeviceProduct=RMX3301 \
    SystemDevice=RED8ACL1 \
    SystemName=RMX3301
