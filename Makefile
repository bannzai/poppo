XCODEPROJ := Poppo.xcodeproj
SCHEME := Poppo
CONFIGURATION := Debug
DERIVED_DATA := tmp/DerivedData
APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphonesimulator/Poppo.app
IOS_APP := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)-iphoneos/Poppo.app
BUNDLE_ID := com.bannzai.poppo
SIMULATOR_UDID ?= $(shell SCRIPT_QUIET=1 sim-boot | sed -n 's/^DEVICE_UDID=//p' | tail -n 1)
DESTINATION ?= platform=iOS Simulator,id=$(SIMULATOR_UDID)
# 実機ビルドの署名に使う Team ID。public リポジトリのため project.pbxproj に書かず、fastlane と同じ環境変数から渡す
DEVELOPMENT_TEAM ?= $(FASTLANE_TEAM_ID)

.PHONY: build-ios build-ios-device device install-device ios test clean verify

# Simulator 向けビルド。generic destination なら simulator の起動なしでビルドできる
build-ios:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build

# 実機向けの SDK でのビルドだけを、署名なしで行う (実機には入れられない)。
# ScreenCaptureKit は iOS Simulator の SDK に入っておらず、画面の取り込みの実体 (Poppo/ScreenCapture/SystemScreenCaptureSource.swift) は
# simulator 向けビルドではコンパイルされないため、コンパイルが通ることをこの target で確かめる
build-ios-device:
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination 'generic/platform=iOS' CODE_SIGNING_ALLOWED=NO build

# 実機向けビルド。code signing が必要なため、provisioning profile の自動生成とこの Mac へのデバイス登録を CLI から行えるようにする
device:
	@[ -n "$(DEVELOPMENT_TEAM)" ] || { echo "Error: DEVELOPMENT_TEAM が空です (FASTLANE_TEAM_ID を export するか DEVELOPMENT_TEAM=<Team ID> で指定してください)" >&2; exit 1; }
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -configuration $(CONFIGURATION) -derivedDataPath $(DERIVED_DATA) -destination 'generic/platform=iOS' -allowProvisioningUpdates -allowProvisioningDeviceRegistration DEVELOPMENT_TEAM=$(DEVELOPMENT_TEAM) build

# 実機ビルドを実機にインストールする。インストール先の解決順: DEVICE 変数 (名前 / UDID) > 環境変数 IOS_DEVICE_UDID > devicectl の JSON から実機を自動解決 (決め方は scripts/resolve-physical-device.sh。決められなければ指定を求め、JSON を読めない・jq が無い時はスクリプトのエラーで止まる)
install-device: device
	@set -e; \
	mkdir -p tmp; \
	device="$(DEVICE)"; \
	[ -n "$$device" ] || device="$(IOS_DEVICE_UDID)"; \
	if [ -z "$$device" ]; then \
		xcrun devicectl list devices --json-output tmp/devices.json > /dev/null; \
		device=$$(bash scripts/resolve-physical-device.sh tmp/devices.json) || { code=$$?; [ "$$code" -eq 1 ] || exit "$$code"; }; \
	fi; \
	[ -n "$$device" ] || { echo "Error: 実機が見つかりません (IOS_DEVICE_UDID を export するか DEVICE=<名前|UDID> で指定してください)" >&2; exit 1; }; \
	xcrun devicectl device install app --device "$$device" "$(IOS_APP)"; \
	xcrun devicectl device process launch --device "$$device" $(BUNDLE_ID)

# Simulator 向けビルドを sim-boot で起動したプロジェクト固有 simulator にインストールして起動する
ios: build-ios
	@set -e; \
	simulator_udid="$(SIMULATOR_UDID)"; \
	[ -n "$$simulator_udid" ] || { echo "Error: sim-boot で Simulator を解決できません (sim-boot が PATH にあるか確認するか、SIMULATOR_UDID=<UDID> を指定してください)" >&2; exit 1; }; \
	xcrun simctl install "$$simulator_udid" $(APP); \
	xcrun simctl launch "$$simulator_udid" $(BUNDLE_ID)

# 署名は切らない (CODE_SIGNING_ALLOWED=NO を付けない): 署名の無いアプリは entitlements を持たず、Keychain の操作が
# errSecMissingEntitlement (-34018) で失敗するため (API キーの保存のテスト。CI の実測: https://github.com/bannzai/poppo/actions/runs/44855185498 )
test:
	@set -e; \
	destination="$(DESTINATION)"; \
	[ -n "$$destination" ] && [ "$$destination" != "platform=iOS Simulator,id=" ] || { echo "Error: sim-boot で Simulator を解決できません (sim-boot が PATH にあるか確認するか、DESTINATION='<destination>' または SIMULATOR_UDID=<UDID> を指定してください)" >&2; exit 1; }; \
	xcodebuild -project $(XCODEPROJ) -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA) -destination "$$destination" test

clean:
	rm -rf $(DERIVED_DATA)

# CI (.github/workflows/ci.yml) と同じ検査をローカルでまとめて行う。通常は CI に任せ、CI では原因を調べられない時だけ使う
verify: build-ios build-ios-device test

# 引数なしの make で ios を実行する (人が手で動作確認するための入口。検査・テストは CI が行う)
.DEFAULT_GOAL := ios

# build-ios・build-ios-device・test は同じ DerivedData を使うため、-j 指定でも並列に起動させない (各 target は xcodebuild 1 本で、make 側の並列化で速くなるものは無い)
.NOTPARALLEL:
