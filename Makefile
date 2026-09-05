# Clutch — native iOS beta app + local backend
#
# Requires: Xcode 26+, Homebrew, xcodegen, firebase-tools, Java (for emulators).
# Run `make doctor` to check your machine.

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
export DEVELOPER_DIR

IOS_DIR      := ios
XCODEPROJ    := $(IOS_DIR)/Clutch.xcodeproj
SCHEME       := Clutch
SIM_DEST     := platform=iOS Simulator,name=iPhone 17
FIREBASE_PROJECT := demo-clutch

.PHONY: help doctor project deps emulators emulators-persist app test build clean seed

help:
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

doctor: ## Check that all required tools are installed
	@echo "Xcode:      $$( (xcodebuild -version 2>/dev/null | head -1) || echo 'MISSING — see ios/README.md')"
	@echo "xcodegen:   $$(xcodegen --version 2>/dev/null || echo MISSING)"
	@echo "firebase:   $$(firebase --version 2>/dev/null || echo MISSING)"
	@echo "java:       $$(java -version 2>&1 | head -1 || echo 'MISSING — brew install openjdk')"
	@echo "node:       $$(node --version 2>/dev/null || echo MISSING)"

project: ## Regenerate Clutch.xcodeproj from ios/project.yml
	cd $(IOS_DIR) && xcodegen generate

deps: project ## Resolve Swift Package (Firebase) dependencies
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -resolvePackageDependencies

emulators: ## Start the Firebase Local Emulator Suite (auth + firestore + UI on :4000)
	firebase emulators:start --only auth,firestore --project $(FIREBASE_PROJECT)

emulators-persist: ## Same, but save/restore emulator data between runs
	firebase emulators:start --only auth,firestore --project $(FIREBASE_PROJECT) \
		--import ./emulator-data --export-on-exit ./emulator-data

build: deps ## Build the app for the iOS Simulator
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) \
		-destination 'generic/platform=iOS Simulator' -configuration Debug build

test: deps ## Run the unit tests on a simulator
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) \
		-destination '$(SIM_DEST)' test

app: ## Build, install and launch the app on a booted simulator (run `make emulators` first)
	@open -a Simulator
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) \
		-destination '$(SIM_DEST)' -configuration Debug \
		-derivedDataPath build install
	xcrun simctl install booted "$$(find build -name 'Clutch.app' -path '*iphonesimulator*' | head -1)"
	xcrun simctl launch --console booted com.clutch.mobile

seed: ## Seed the running Firestore emulator with sample data
	cd scripts && npm install --silent && node seed-emulator.mjs

clean: ## Remove build artifacts
	rm -rf $(IOS_DIR)/build build $(IOS_DIR)/DerivedData
