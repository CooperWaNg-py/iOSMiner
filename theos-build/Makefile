# iOSMiner — Theos Makefile for rootless jailbreak .deb
# Targets iPad 6th gen (A10 / arm64) running iPadOS 17.7.10 with palera1n rootless

# Rootless jailbreak (palera1n)
THEOS_PACKAGE_SCHEME = rootless

# Target SDK and deployment
ARCHS = arm64
TARGET = iphone:17.0:17.0

include $(THEOS)/makefiles/common.mk

# =============================================================================
# Main Application
# =============================================================================

APPLICATION_NAME = iOSMiner

# Swift source files (from the Xcode project)
iOSMiner_SWIFT_FILES = \
	../iOSMiner/iOSMinerApp.swift \
	../iOSMiner/ContentView.swift \
	../iOSMiner/SettingsView.swift \
	../iOSMiner/StatsView.swift \
	../iOSMiner/MiningManager.swift \
	../iOSMiner/StratumClient.swift \
	../iOSMiner/MiningEngine.swift \
	../iOSMiner/SHA256Util.swift \
	../iOSMiner/MiningMode.swift \
	../iOSMiner/BackgroundHelper.swift \
	../iOSMiner/DevFeeManager.swift \
	../iOSMiner/LogsView.swift \
	../iOSMiner/GlobalStats.swift \
	../iOSMiner/PoolPreset.swift \
	../iOSMiner/SharedMiningData.swift \
	../iOSMiner/ScreensaverView.swift \
	../iOSMiner/NotificationManager.swift

# Frameworks needed (includes WidgetKit for reloadAllTimelines)
iOSMiner_FRAMEWORKS = UIKit SwiftUI Foundation Network CryptoKit AVFoundation AVFAudio WidgetKit UserNotifications QuartzCore
iOSMiner_EXTRA_SWIFTFLAGS = -import-underlying-module
iOSMiner_SWIFT_BRIDGING_HEADER =

# Code signing entitlements
iOSMiner_CODESIGN_FLAGS = -SEntitlements.plist

# Resources (Assets, etc.)
iOSMiner_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk

# =============================================================================
# Widget Extension (.appex)
# =============================================================================

APPEX_NAME = iOSMinerWidget

iOSMinerWidget_SWIFT_FILES = widget/iOSMinerWidget.swift
iOSMinerWidget_FRAMEWORKS = SwiftUI WidgetKit
iOSMinerWidget_CODESIGN_FLAGS = -Swidget/WidgetEntitlements.plist
iOSMinerWidget_INSTALL_PATH = /Applications/iOSMiner.app/PlugIns

include $(THEOS_MAKE_PATH)/appex.mk

# Copy widget Info.plist into the built .appex bundle
after-iOSMinerWidget-all::
	@cp widget/Info.plist $(THEOS_OBJ_DIR)/iOSMinerWidget.appex/Info.plist
	@echo "Widget Info.plist copied."

# =============================================================================
# Post-build: Icons and Info.plist
# =============================================================================

ICON_SRC = icon.png
ICON_DEST = $(THEOS_OBJ_DIR)/iOSMiner.app

# Post-build: copy Info.plist and generate icon sizes from icon.png
after-iOSMiner-all::
	@cp Info.plist $(ICON_DEST)/Info.plist
	@if [ -f "$(ICON_SRC)" ]; then \
		echo "Generating app icons from $(ICON_SRC)..."; \
		sips -z 120 120 --out "$(ICON_DEST)/AppIcon60x60@2x.png" "$(ICON_SRC)" > /dev/null 2>&1; \
		sips -z 180 180 --out "$(ICON_DEST)/AppIcon60x60@3x.png" "$(ICON_SRC)" > /dev/null 2>&1; \
		sips -z 152 152 --out "$(ICON_DEST)/AppIcon76x76@2x.png" "$(ICON_SRC)" > /dev/null 2>&1; \
		sips -z 167 167 --out "$(ICON_DEST)/AppIcon83.5x83.5@2x.png" "$(ICON_SRC)" > /dev/null 2>&1; \
		sips -z 1024 1024 --out "$(ICON_DEST)/AppIcon1024x1024.png" "$(ICON_SRC)" > /dev/null 2>&1; \
		echo "Icons generated."; \
	else \
		echo "Warning: $(ICON_SRC) not found — no app icon will be included."; \
	fi
