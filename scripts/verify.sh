#!/bin/zsh

set -euo pipefail

ai_invest_root=${0:A:h:h}
ai_invest_derived=${TMPDIR:-/tmp}/AIInvestVerifyDerivedData
ai_invest_core_tests=${TMPDIR:-/tmp}/AIInvestCoreRegressionTests
ai_invest_module_cache=${TMPDIR:-/tmp}/AIInvestSwiftModuleCache
ai_invest_xcodebuild=/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild
ai_invest_swiftc=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
ai_invest_sdk=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)

cd "$ai_invest_root"

echo "[1/3] 运行核心回归测试"
"$ai_invest_swiftc" -parse-as-library -module-name AIInvestCoreRegression \
  -j 1 \
  -sdk "$ai_invest_sdk" -target arm64-apple-macos14.0 \
  -module-cache-path "$ai_invest_module_cache" \
  AIInvest/Models/InvestmentModels.swift \
  AIInvest/Models/LearningModels.swift \
  AIInvest/App/PreviewData.swift \
  AIInvest/App/LearningCurriculum.swift \
  AIInvest/Services/InvestmentServices.swift \
  AIInvest/Services/ManualHoldingStore.swift \
  AIInvest/Services/InvestmentDatabase.swift \
  AIInvest/Services/LearningWorkspaceService.swift \
  AIInvest/Services/LongbridgeCLIService.swift \
  AIInvest/Services/OpenAIResearchService.swift \
  AIInvest/Services/CodexInvestmentService.swift \
  AIInvest/App/AppModel.swift \
  scripts/CoreRegressionTests.swift \
  -framework AppKit -framework Security -lsqlite3 \
  -o "$ai_invest_core_tests"
"$ai_invest_core_tests"

echo "[2/3] 构建 Debug"
"$ai_invest_xcodebuild" -quiet \
  -project AIInvest.xcodeproj \
  -scheme AIInvest \
  -configuration Debug \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$ai_invest_derived" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "[3/3] 构建 Release"
"$ai_invest_xcodebuild" -quiet \
  -project AIInvest.xcodeproj \
  -scheme AIInvest \
  -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$ai_invest_derived" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "AI Invest 核心回归、Debug / Release 构建全部通过。"
