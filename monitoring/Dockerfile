# Java 21로 Collector/Web 구동
FROM eclipse-temurin:21-jdk-jammy AS builder
WORKDIR /monitoring

ARG PINPOINT_VERSION=3.0.3
ARG HBASE_VERSION=2.2.6
ENV PINPOINT_VERSION=${PINPOINT_VERSION} \
    HBASE_VERSION=${HBASE_VERSION} \
    LANG=C.UTF-8

# 필수 도구
RUN apt-get update && apt-get install -y --no-install-recommends \
      curl ca-certificates bash tini procps netcat-openbsd \
    && rm -rf /var/lib/apt/lists/*

# 실행 사용자
RUN useradd -m -u 10001 -s /bin/bash pinpoint
WORKDIR /opt/pinpoint

# ---- HBase 2.2.6 설치 ----
RUN curl -fL "https://archive.apache.org/dist/hbase/${HBASE_VERSION}/hbase-${HBASE_VERSION}-bin.tar.gz" -o /tmp/hbase.tgz \
 && tar -xzf /tmp/hbase.tgz -C /opt \
 && ln -s /opt/hbase-${HBASE_VERSION} /opt/hbase \
 && mkdir -p /opt/hbase-data /opt/hbase-zk /var/log/hbase \
 && rm -f /tmp/hbase.tgz

# HBase 설정파일
COPY monitoring/hbase-site.xml /opt/hbase/conf/hbase-site.xml
RUN set -eux; \
    echo 'export HBASE_MANAGES_ZK=true'                    >> /opt/hbase/conf/hbase-env.sh; \
    echo 'export HBASE_LOG_DIR=${HBASE_LOG_DIR:-/var/log/hbase}' >> /opt/hbase/conf/hbase-env.sh; \
    echo 'export HBASE_HEAPSIZE=${HBASE_HEAPSIZE:-512}'    >> /opt/hbase/conf/hbase-env.sh; \
    # (JDK8 전용 옵션 경고 방지용 주석화)
    sed -ri 's/^(.*PermSize=.*)$/# \1/g' /opt/hbase/conf/hbase-env.sh || true

# ---- HBase 전용 JRE 8 번들 ----
RUN apt-get update && apt-get install -y openjdk-8-jre && rm -rf /var/lib/apt/lists/*

# ---- Pinpoint HBase 스크립트/서버 JAR(3.0.3) ----
RUN curl -fL "https://raw.githubusercontent.com/pinpoint-apm/pinpoint/v${PINPOINT_VERSION}/hbase/scripts/hbase-create.hbase" \
      -o /opt/pinpoint/hbase-create.hbase \
 && curl -fL "https://github.com/pinpoint-apm/pinpoint/releases/download/v${PINPOINT_VERSION}/pinpoint-collector-boot-${PINPOINT_VERSION}.jar" \
      -o /opt/pinpoint/pinpoint-collector-boot-${PINPOINT_VERSION}.jar \
 && curl -fL "https://github.com/pinpoint-apm/pinpoint/releases/download/v${PINPOINT_VERSION}/pinpoint-web-boot-${PINPOINT_VERSION}.jar" \
      -o /opt/pinpoint/pinpoint-web-boot-${PINPOINT_VERSION}.jar

# 실행 스크립트
COPY monitoring/start.sh /opt/pinpoint/start.sh
RUN chmod +x /opt/pinpoint/start.sh \
 && chown -R pinpoint:pinpoint /opt/hbase* /var/log/hbase /opt/pinpoint /opt/jre8

USER pinpoint
EXPOSE 8080 9991 9992 9993 16010
VOLUME ["/opt/hbase-data","/opt/hbase-zk"]

HEALTHCHECK --interval=30s --timeout=5s --retries=5 \
  CMD nc -z 127.0.0.1 8080 || exit 1

ENTRYPOINT ["/usr/bin/tini","--","/opt/pinpoint/start.sh"]
