#!/usr/bin/env bash
set -euo pipefail

# ------------ 기본값 (필요 시 환경변수로 덮어쓰기) ------------
: "${PINPOINT_VERSION:=3.0.3}"
: "${WEB_PORT:=8080}"
: "${SPRING_PROFILES_ACTIVE:=release}"
: "${ZK_QUORUM:=localhost}"             # 외부 ZK 쓰면 값 변경
: "${HBASE_HEAPSIZE:=512}"              # 메모리 여유 있으면 1024~ 권장
: "${HBASE_LOG_DIR:=/var/log/hbase}"

# ------------ 경로 ------------
export HBASE_HOME=/opt/hbase
export HBASE_LOG_DIR
export HBASE_HEAPSIZE

# 컨테이너 기본 JAVA_HOME(Temurin 21)을 앱용으로 보관
APP_JAVA_HOME="${JAVA_HOME:-/opt/java/openjdk}"
# HBase 전용 Java 8
HBASE_JAVA_HOME="/opt/jre8"

echo "[env] APP_JAVA_HOME=${APP_JAVA_HOME}"
echo "[env] HBASE_JAVA_HOME=${HBASE_JAVA_HOME}"
echo "[env] ZK_QUORUM=${ZK_QUORUM}"

# hbase-site.xml에 ZK_QUORUM 반영
sed -ri "s#(<name>hbase.zookeeper.quorum</name>[[:space:]]*<value>)[^<]+(</value>)#\1${ZK_QUORUM}\2#" \
  "${HBASE_HOME}/conf/hbase-site.xml"

# ------------ HBase 시작 (내장 ZK) ------------
echo "[hbase] starting with Java8..."
JAVA_HOME="${HBASE_JAVA_HOME}" "${HBASE_HOME}/bin/start-hbase.sh"

# HBase master up 대기
echo "[hbase] waiting for master..."
for i in {1..60}; do
  if echo "status 'simple'" | JAVA_HOME="${HBASE_JAVA_HOME}" "${HBASE_HOME}/bin/hbase" shell -n 2>/dev/null | grep -qi 'active master'; then
    echo "[hbase] master is active"
    break
  fi
  sleep 2
done

# Pinpoint 테이블 생성(idempotent)
echo "[hbase] creating Pinpoint tables..."
JAVA_HOME="${HBASE_JAVA_HOME}" "${HBASE_HOME}/bin/hbase" shell -n /opt/pinpoint/hbase-create.hbase || true

# ------------ Pinpoint Collector (Java21) ------------
echo "[collector] starting (Java21)..."
JAVA_HOME="${APP_JAVA_HOME}" exec -a collector java ${JAVA_OPTS:-} \
  -Dspring.profiles.active="${SPRING_PROFILES_ACTIVE}" \
  -Dpinpoint.zookeeper.address="${ZK_QUORUM}" \
  -jar "/opt/pinpoint/pinpoint-collector-boot-${PINPOINT_VERSION}.jar" &
COLLECTOR_PID=$!

# ------------ Pinpoint Web (Java21) ------------
echo "[web] starting (Java21) on :${WEB_PORT}..."
JAVA_HOME="${APP_JAVA_HOME}" exec -a web java ${JAVA_OPTS:-} \
  -Dspring.profiles.active="${SPRING_PROFILES_ACTIVE}" \
  -Dpinpoint.zookeeper.address="${ZK_QUORUM}" \
  -Dserver.port="${WEB_PORT}" \
  ${EXTRA_WEB_JAVA_OPTS:-} \
  -jar "/opt/pinpoint/pinpoint-web-boot-${PINPOINT_VERSION}.jar" &
WEB_PID=$!

trap 'echo "[trap] stopping..."; kill ${COLLECTOR_PID} ${WEB_PID} || true; exit 0' SIGTERM SIGINT
wait -n ${COLLECTOR_PID} ${WEB_PID}

