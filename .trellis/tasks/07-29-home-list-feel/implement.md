# Home 列表手感 — 实施

## Steps

1. 梳理 `HomeViewController` 中 refresh / loadMore / tab bar freeze 调用图，写进本目录 `research/callgraph.md`（短文即可）。
2. 在 `HomeViewModel` 固化 `beginRefresh/endRefresh/beginLoadMore/endLoadMore` 门闩（若已有则补测试）。
3. 修 VC：确保所有结束路径 `endRefreshing`；load-more 触发点唯一。
4. 校准 scrollViewDidScroll 中 freeze 条件，去掉“no-op loadMore 永久 lock”类坑。
5. 缓存失败路径：解码失败删除缓存并走网络。
6. 测试：VM 去重；可选 UI 测试不做强制。
7. 手动 checklist：冷启动、下拉、猛滑到底、失败重试、空列表。

## Validation

```bash
# 定向测试（名称以仓库现有为准，可增补）
xcodebuild test -workspace dexoflux-build.xcworkspace -scheme dexoflux \
  -destination 'platform=iOS Simulator,id=<iphone16-id>' \
  -only-testing:dexofluxTests/<HomeRelatedTests> \
  -derivedDataPath /tmp/dexo-home-dd CODE_SIGNING_ALLOWED=NO
```

手动：Home 连续操作 2 分钟无异常跳动。

## Done in code
- loadTopics single-flight
- loadMore blocks during refresh
- willDisplay task gate
- HomeListLoadingGateTests
