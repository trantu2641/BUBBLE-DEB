# BubbleMe extracted rebuild

This repository was reconstructed from `BubbleMe-0.0.2-alpha-1+roothide-iphoneos-arm64e.deb`.

The original `BubbleMe.dylib` and preference bundle are preserved as prebuilt payload. The new `BubbleMeOrientationFix.dylib` is a conservative companion tweak: it only finds `BMBubbleWindow` and asks that window to relayout after device-orientation changes. It deliberately does **not** force Portrait/Landscape, change SpringBoard orientation, or apply a global screen transform.

## Important
The original DEB did not contain C/Objective-C source code, only compiled Mach-O binaries. Therefore the original BubbleMe source cannot be losslessly recovered from the DEB. This repo is a safe rebuild scaffold, not a decompilation of the original source.

## Build
Run GitHub Actions -> Build BubbleMe.

Install the resulting DEB. Keep the original DEB available so you can remove/revert if necessary.
