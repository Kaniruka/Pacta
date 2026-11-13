# 旧包云上传恢复（2026-11-13）

用户要求保住小米手机上的 `com.pacta.pacta` 数据并上传云端，明确授权 root 导出。

## 结论

登录有效（Auth user HTTP 200），读取云端预览成功。部署的 `save_cloud_business_snapshot` 仅支持原 7 参数；客户端增加 `p_device_manufacturer`、`p_device_model` 后调用 9 参数版本，服务器返回 HTTP 404 / PGRST202，hint 明确指向旧 7 参数签名。现有 UI 把非 StateError 统一显示成网络/登录错误，因此误导排障。没有证据表明本地数据丢失或登录失效。

## 数据保护与恢复结果

- 旧应用没有卸载、清数据、退出登录、覆盖安装或下载云数据到手机。
- root 导出前短暂停止应用，完整保存原私有目录、设备保护目录和已安装 APK；备份目录限制为当前 Windows 用户及 SYSTEM。备份在仓库之外的受限本机目录，具体位置仅保留于本机恢复记录；包含认证会话，不能共享。
- 有效归档 `private-data-validated.tar.gz` 和上传前新归档 `pre-upload-private-data.tar.gz` 均通过 gzip CRC/归档检查；数据库 quick_check=ok，user_version=25。初次直接流式归档 CRC 失败，未作为有效备份使用。
- 使用应用的 `CloudSnapshotRepository.captureLocalState` 从备份副本导出；157 条，无未完成专注/预约。未手写转换数据库业务字段。
- 上传前保存完整云端旧副本（58 条、revision 1）。通过旧 7 参数 RPC 保留 expectedRevision 乐观并发保护，上传 157 条。
- 上传后重新读取：revision 2、row_count 157；完整 payload 的每张表、每个字段与导出副本相等。云端回读存于受限备份目录。业务数据与令牌不写入源码、日志或此报告。
- 旧应用已重开；之后手机锁屏，未绕过锁屏或再操作界面。此次上传由受保护的恢复脚本完成，旧安装包本身未改，因此旧界面的“上次同步”本机记录可能仍显示原日期。

## 客户端修复

`SupabaseCloudSnapshotRemote.upload` 仅在明确的 PGRST202 中，message 对应本 RPC 9 参数且 hint 对应原 7 参数时重试一次，去掉可选硬件信息；payload、revision、legacy token 均不变。初次请求没有匹配函数、未执行写入才允许重试；认证、权限、冲突、网络及其他缺函数错误不盲目重试。重试前重新核验当前用户，第二次错误保留原映射，不继续重试。没有部署 SQL、修改 RLS 或更改认证。

## 验证

- 子 Agent 红绿回归及相关测试：44 项通过；flutter analyze --no-pub 无问题。
- 主 Agent 独立：`flutter test --no-pub --reporter compact`，402 项通过，日志 `build/old-package-sync-20261113/full-tests.log`。
- 真实身份读取、只读接口契约探测、受版本保护的真实上传及全量回读校验均已执行。
- 备份目录内 `verified-manifest.json` 记录有效备份、APK、导出快照及云端前后副本的 SHA-256。
- 修复版 APK 使用仅包含 SUPABASE_URL、SUPABASE_PUBLISHABLE_KEY 的公开配置构建；不含恢复会话、测试账号或服务端密钥。旧包未替换，原数据继续保留。
