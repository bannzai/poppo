# 0001. Xcode プロジェクトを直接管理する

## Status
Accepted (2026-11-17)

## Context
最初の `Poppo.xcodeproj` は XcodeGen で組み立てた。XcodeGen の入力 (`project.yml`) と生成物 (`project.pbxproj`) を両方 Git で管理すると、片方だけが更新されても検出できず、後から XcodeGen を実行した時に初めて不一致が表面化する。Xcode の GUI で加えた変更は `project.yml` に反映されず、次の生成で失われる。bannzai/mementomorning では、複数のブランチが同じターゲットを変更した時に再生成で `project.pbxproj` 全体が書き換わって競合し、ビルドが失敗した (bannzai/mementomorning の `documents/adr/0002-manage-xcode-project-directly.md`)。

## Decision
`project.yml` をリポジトリに置かず、`Poppo.xcodeproj` をプロジェクト構成の唯一の正として直接管理する。XcodeGen は使わず、`xcodegen generate` を実行しない。

ソースのディレクトリ (`Poppo/`・`PoppoKeyboard/`・`PoppoTests/`) は Xcode の同期フォルダ (`PBXFileSystemSynchronizedRootGroup`) としてターゲットに結び付ける。ディレクトリにファイルを足す・消すだけでターゲットに反映され、ファイルの追加のたびに `project.pbxproj` を編集しなくてよい。

ターゲット、Build Settings、Build Phases、Scheme、Swift Package の変更は Xcode の GUI で行う。自動化が必要な場合は、プロジェクト構成を `Poppo.xcodeproj/project.pbxproj`、Scheme を `Poppo.xcodeproj/xcshareddata/xcschemes/*.xcscheme` で直接編集する。

## Consequences

**良い点:**
- `project.yml` と `project.pbxproj` の二重管理が無く、不一致によるビルド失敗が起きない
- 並行するブランチがそれぞれファイルを足しても、`project.pbxproj` が競合しない (同期フォルダ)

**悪い点 / 引き受けるリスク:**
- `project.pbxproj` の差分は YAML より読みづらいため、プロジェクト構成を変えた時は `git diff -- Poppo.xcodeproj` で意図した差分だけであることを確かめ、CI のビルドとテストで検証する
- 同期フォルダの中のファイルは全てターゲットに入る。ターゲットに入れたくないファイル (拡張の Info.plist 等) は同期フォルダの外 (`Config/`) に置く
