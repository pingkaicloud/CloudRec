# CloudRec TKE DEV 镜像发布

## 部署目标

复用 Clinic 的上海 Runner、上海 TCR 和 GitHub Actions 发布方式。
部署目标为 Clinic TKE DEV 的独立 `cloudsec-dev` namespace。
App Delivery 仅更新 `shaotao/cloudsec` 测试分支，不更新 `main`。

## 验证和发布

PR 和 `shaotao/cloudsec` 分支推送只构建、验证，不发布镜像或部署集群。
`deploy/tke/smoke.sh` 在临时 Docker 网络中初始化 MySQL，验证应用启动和前端静态资源。
临时测试结束后删除测试容器和网络。测试不连接实际云账号。

审核后在测试分支 HEAD 创建 `cloudsec-dev-image-<完整提交 SHA>` 标签，触发 DEV 发布。
不要移动或覆盖已有标签。该标签会更新 App Delivery 并触发 DEV 部署。
发布前须确认两个仓库的配置、权限和 namespace 初始化已经完成。

应用镜像和 MySQL 镜像发布到 `clinic.tencentcloudcr.com/clinic-dev`。
交付配置使用不可变 digest。源码发布任务等待 App Delivery 的实际部署结果。
失败时保留工作流记录，不改用本机构建或直接 apply。

## 配置要求

CloudRec 仓库需要 `TCR_DEPLOY_USERNAME`、`TCR_DEPLOY_PASSWORD`、`GIT_ACTION_BOT`。
它们属于新项目的发布配置，不能假定 Clinic 的仓库级 Secret 自动共享。
App Delivery 需要独立的 `CLOUDSEC_DEV_CICD_KUBECONFIG_B64`。
完整 bootstrap、SSM、采集器和访问步骤见：

https://github.com/pingkaicloud/app-delivery/blob/shaotao/cloudsec/cloudsec/README.md

## 与上游镜像的区别

- Java 和 Go 在 Linux/amd64 构建，保留当前仓库已提交的前端产物。
- OPA 从固定版本镜像复制，避免在启动时下载可执行文件。
- 应用使用非 root 用户，数据库连接使用独立的 `cloudrec` 用户。
- Java 和 OPA 由入口脚本共同管理，任一进程退出都会终止容器。
- 采集器作为独立工作负载运行，通过文件读取 Token。
- 初始化 SQL 随应用镜像发布，由 MySQL initContainer 提供。

本次不修改业务代码；Maven 保留上游默认的单元测试跳过设置。
新增运行态验收在 CI 的临时 MySQL 中执行，不能把构建成功当成所有单元测试通过。
若后续修改 Java 或 Go 业务代码，需要补跑对应测试套件。
