# 主路径打磨 — 总实施计划

## Wave 0 — 基线

1. 记录当前 simulator build 命令与主路径手动 checklist。
2. 提交/隔离无关工作区改动（如分享图图文混排可独立 commit）。
3. 五个子任务保持 `planning`，用户审完 PRD/design 后再 `task.py start` 逐个开。

## Wave 1 — A Home 列表手感

见 `07-29-home-list-feel/implement.md`。

## Wave 2 — C CF/会话/图片

见 `07-29-cf-session-images/implement.md`。可与 A 尾声重叠做只读调研。

## Wave 3 — B 详情流畅

见 `07-29-topic-detail-perf/implement.md`。

## Wave 4 — D 列表基建收口

见 `07-29-list-infra-integration/implement.md`。输入是 A 的稳定契约。

## Wave 5 — E 神文件拆分

见 `07-29-god-file-split/implement.md`。只在 A/B 行为锁定后进行。

## 全局验证命令

```bash
/Applications/Xcode.app/Contents/Developer/usr/bin/xcodebuild build \
  -workspace dexoflux-build.xcworkspace \
  -scheme dexoflux \
  -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/dexo-mainpath-dd \
  CODE_SIGNING_ALLOWED=NO
```

不启动 App 部署到实体设备作为 CI 门槛；手动验收在模拟器完成。
