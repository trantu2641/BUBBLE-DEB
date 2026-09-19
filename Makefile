export THEOS ?= $(HOME)/theos

ARCHS = arm64e
TARGET = iphone:clang:16.5:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = BubbleMeOrientationFix

BubbleMeOrientationFix_FILES = OrientationFix.m

BubbleMeOrientationFix_CFLAGS = \
    -fobjc-arc \
    -Wno-deprecated-declarations

BubbleMeOrientationFix_FRAMEWORKS = \
    UIKit \
    Foundation

include $(THEOS_MAKE_PATH)/tweak.mk
