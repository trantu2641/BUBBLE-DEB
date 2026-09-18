ARCHS = arm64e
TARGET = iphone:clang:16.5:15.0
THEOS_PACKAGE_SCHEME = roothide
INSTALL_TARGET_PROCESSES = SpringBoard

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BubbleMeOrientationFix
BubbleMeOrientationFix_FILES = OrientationFix.m
BubbleMeOrientationFix_CFLAGS = -fobjc-arc
BubbleMeOrientationFix_FRAMEWORKS = UIKit

include $(THEOS_MAKE_PATH)/tweak.mk
