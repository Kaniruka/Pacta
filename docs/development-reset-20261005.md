# 开发数据重置验证（2026-10-05）

用户明确说明当前没有正式用户，授权删除所有既有开发数据和测试身份，仅保留一个管理员。此操作是一次性开发环境重置，不改变产品的30天停用清理流程。

## 执行与结果

- 根据本机受保护配置与已链接项目标识核对目标开发项目，两者一致。通过管理API查询确认Auth有13个用户、app_admins恰有1个管理员，且与本机管理员配置匹配。管理员密码登录也成功。未输出或提交账号、密码、UUID与密钥。
- 核查public表全集与外键边界，并确认Storage对象数为0。显式事务清空除app_admins外的15张public表（包含旧业务表、全量云快照、注册资格、停用记录和清理回执），不使用跨表CASCADE扩展删除。
- 使用Auth Admin API永久删除12个非管理员身份，以已核对的管理员UUID为保护边界。
- 管理API最终独立查询：Auth用户数1、管理员数1、保留管理员存在；15张public数据表均为0行。
- Windows进程列表确认pacta.exe未运行；只读SQLite确认目标为Pacta schema22数据库。删除Documents/pacta.sqlite及存在的SQLite边车文件，验证数据库文件不存在。删除Pacta专用shared_preferences.json并验证不存在，从而清除本机旧会话和偏好缓存。
- 本轮最初网络连接失败未执行任何写入；连接诊断后重新执行成功。

数据库结构、RLS、管理函数与管理员凭据保留。开发重置不写入客户端自动擦库逻辑。尚未检查未连接的其他设备缓存；本轮已连接Android设备未查到Pacta安装包。之后的UI验证使用独立内存样例，不向清空后的开发项目写入测试用户或业务数据。

管理接口依据：[Management API Run a query](https://supabase.com/docs/reference/api/v1-run-a-query)、[Get project API keys](https://supabase.com/docs/reference/api/v1-get-project-api-keys)、[Auth Admin deleteUser](https://supabase.com/docs/reference/javascript/auth-admin-deleteuser)。
