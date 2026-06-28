# 运营后台 · 假数据 · 管理员（实现说明）

> 给运营/接手的开发（含本地 Claude Code）看：解释「冷启动假用户 + 每日自动滑入 + App 内管理员后台」是怎么实现的、怎么用、怎么清。

## 目的
新 App 朋友圈/广场空，没人愿意留。注入一批**逼真示例用户 + 朋友圈**充门面引流；假账号带标记，等真用户进来后**一键清空**；并提供**管理员后台**手动运营。

## 关键文件
- `backend/app/models.py`：`User.is_seed`（假用户标记）、`User.is_admin`（管理员）、`SeedState`（每日滑入按天幂等）。`User.public_dict` 含 `is_admin/is_seed`。
- `backend/app/seed_assets.py`：随仓库提交的真实占位照片池，拷到 `STORAGE_DIR/seed/`，经 `/media/seed/<file>` 提供；`pick_avatar()/pick_moment()` 轮换发 URL。
- `backend/seed_assets/avatars/*.jpg`（40）+ `moments/*.jpg`（60）：**随仓库走的图片**，后端自托管，国内可访问、不依赖外网。
- `backend/app/seed_population.py`：内容库 + `create_fake_user/post_moment_as` + `seed_initial_population`（首批 20 人 50 条）+ `generate_users` + `daily_tick`（每日滑入）+ `purge_user/purge_all_seed`（级联清理）。
- `backend/app/routes/admin_routes.py`：所有 `/admin/*` 接口（经 `deps.get_admin_user` 鉴权）。
- `backend/app/main.py`：`_migrate` 补列、按 env 引导管理员、启动跑首批种子、`@app.on_event("startup")` 起每日滑入后台循环。
- iOS：`FlowApp/Sources/Features/Admin/AdminView.swift`、`FakeUserDetailView.swift`；入口在 `Features/Settings/SettingsView.swift`（仅 `auth.user?.isAdmin` 显示）；API 在 `Networking/APIClient.swift`（`admin*` 方法 + `AdminStats/AdminFakeUser/EmptyResponse`）。

## 环境变量（backend/.env，已 gitignored）
| 变量 | 作用 | 备注 |
|---|---|---|
| `PUBLIC_BASE_URL` | 拼图片 URL 的前缀 | ⚠️ **首次种子前必须设成服务器公网地址**，否则图片 URL 指向 localhost、手机加载不出 |
| `ADMIN_EMAIL` / `ADMIN_PASSWORD` | 启动时引导管理员账号 | 当前为 `admin@parchment.app` / 一个初始密码，登录后建议改 |
| `SEED_DAILY_ENABLED` | 每日滑入开关 | 默认 `true`，设 `false` 关闭 |
| `SEED_DAILY_USERS` | 每天新增假用户数 | 默认 3 |
| `SEED_DAILY_MOMENTS` | 每天新增朋友圈数 | 默认 8 |

## 运行机制
- **首批**：首次启动且还没有任何 `is_seed` 用户时，`seed_initial_population` 灌 20 假用户 + 50 条错峰朋友圈（带点赞/评论）。已存在则跳过（幂等）。
- **每日滑入**：启动后一个 asyncio 循环每 6 小时检查一次，调 `daily_tick`；`SeedState.last_tick_day` 保证**一天只灌一批**（重启安全）。
- **管理员后台**：管理员账号登录 App → 设置页「运营后台」。

## 管理员接口（都需管理员 token）
- `GET /admin/stats`：真/假用户数、朋友圈数。
- `GET /admin/fake-users`、`POST /admin/fake-users`、`POST /admin/fake-users/generate {count}`。
- `POST /admin/fake-users/{id}/moments {content,image_url?}`、`.../companions {name,persona,greeting,tint}`、`.../groups {name,description,member_seed_users}`。
- `DELETE /admin/fake-users/{id}`（删一个 + 级联）、`DELETE /admin/fake-data`（清空所有假数据）。
- `POST /admin/seed/daily-tick`（手动触发今日一批，force）。

## 一键清空
后台红色按钮 = `DELETE /admin/fake-data` = `purge_all_seed`：删除所有 `is_seed` 用户及其朋友圈/点赞/评论/搭子（及记忆等）/拥有的群（连成员、会话、消息）/群成员身份/好友/助手记录。**真实用户与管理员账号不受影响。**

## 图片来源（重要）
- 头像：`i.pravatar.cc`（占位人像，源自 Unsplash 等的**真人**照片）。
- 配图：`picsum.photos`（Lorem Picsum，源自 Unsplash，多为风景/物体）。
- 已下载为 JPG 提交进仓库、后端自托管。
- ⚠️ **风险**：头像是真人脸，正式规模化时存在**肖像权/隐私**隐患。要放量建议把头像换成「AI 生成的虚拟人脸」（不存在的人，无肖像问题）。换法：替换 `backend/seed_assets/avatars/*.jpg` 即可，DB URL 不变（文件名一致）或重新生成后清空重灌。

## 部署清单
1. `backend/.env` 设好 `PUBLIC_BASE_URL`（公网）、`ADMIN_EMAIL`、`ADMIN_PASSWORD`。
2. `git pull` → 重启后端（首批种子自动注入；每日滑入自动开始）。
3. iOS 在 Mac `xcodegen generate` + 重新编译；管理员账号登录见「运营后台」。
4. 想重置：后台「一键清空」后再「生成今日一批」或重启（首批仅在无假用户时才会再灌）。
