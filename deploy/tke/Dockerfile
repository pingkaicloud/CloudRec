FROM maven:3.9.9-eclipse-temurin-17 AS server
WORKDIR /build
COPY . .
# Use the upstream packaged frontend; this change does not modify UI sources.
RUN mvn --batch-mode --no-transfer-progress package

FROM golang:1.25.5-bookworm AS collector
WORKDIR /build
COPY collector/ .
RUN CGO_ENABLED=0 GOARCH=amd64 GOOS=linux go build -trimpath -o /collectors .

FROM openpolicyagent/opa:1.4.2-static AS opa
FROM eclipse-temurin:17.0.15_6-jre-jammy
WORKDIR /cloudrec
RUN groupadd -g 10001 cloudrec && useradd -u 10001 -g cloudrec -d /cloudrec cloudrec \
    && mkdir -p /cloudrec/logs && chown -R 10001:10001 /cloudrec
COPY --from=server --chown=10001:10001 /build/app/bootstrap/target/cloudrec.jar ./cloudrec.jar
COPY --from=collector /collectors ./collectors
COPY --from=opa /opa ./opa
COPY --chown=10001:10001 rules/ ./rules/
COPY --chown=10001:10001 db/init.sql ./db/init.sql
COPY --chown=10001:10001 deploy/tke/entrypoint.sh ./entrypoint.sh
RUN chmod 755 /cloudrec/entrypoint.sh
ENV SPRING_PROFILES_ACTIVE=opensource TZ=Asia/Shanghai
USER 10001:10001
EXPOSE 8080
ENTRYPOINT ["/cloudrec/entrypoint.sh"]
