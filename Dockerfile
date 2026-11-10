# syntax=docker/dockerfile:1
# docker build -t akiba_allinone:4.4.0 .
#
# On a slow route to the default mirrors, point the build at a closer one:
#   docker build -t akiba_allinone:4.4.0 \
#     --build-arg APT_MIRROR=http://mirrors.tuna.tsinghua.edu.cn \
#     --build-arg NPM_REGISTRY=https://registry.npmmirror.com \
#     --build-arg GRADLE_DIST_URL=https://mirrors.cloud.tencent.com/gradle/gradle-8.8-bin.zip \
#     --build-arg MAVEN_MIRROR=https://maven.aliyun.com/repository/public \
#     --build-arg PG_MIRROR=https://mirrors.aliyun.com/postgresql/repos/apt .
#

# ---------------------------------------------------------------------------
# Module jars are compiled from source in a throwaway stage.  They used to be
# checked in under dockerfile_needed/ and silently went stale whenever the
# framework's packages moved — the image then shipped jars referencing
# `org.iotsplab.akiba.llm.agent.AgentModule`, and every manual chat turn died
# with ClassNotFoundException.
# ---------------------------------------------------------------------------
FROM ubuntu:26.04 AS modules

ARG DEBIAN_FRONTEND=noninteractive
# Optional: a closer Ubuntu mirror for slow routes to archive.ubuntu.com.
ARG APT_MIRROR=
RUN if [ -n "$APT_MIRROR" ]; then \
        for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do \
            [ -f "$f" ] && sed -i "s|http://archive.ubuntu.com/ubuntu|${APT_MIRROR}/ubuntu|g" "$f"; \
        done; \
    fi

# Ghidra 12.2 needs Java 25 (application.java.min=25). Ubuntu 26.04 ships it in
# main, so the toolchain comes from the distribution instead of a side download.
RUN apt-get -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::Retries=3 update --fix-missing && \
    apt-get -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::Retries=3 install -y --no-install-recommends openjdk-25-jdk-headless ca-certificates && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY gradle gradle
COPY gradlew gradlew
COPY settings.gradle.kts build.gradle.kts gradle.properties ./
COPY subprojects/akiba_framework subprojects/akiba_framework
COPY subprojects/akiba_db_daemon subprojects/akiba_db_daemon
COPY subprojects/akiba_mod_utils subprojects/akiba_mod_utils
COPY subprojects/akiba_mod_example subprojects/akiba_mod_example
COPY subprojects/akiba_modules subprojects/akiba_modules

# Optional: fetch Gradle itself and Maven artifacts from closer mirrors. Both
# default to the upstream services so a plain `docker build` is unchanged.
ARG GRADLE_DIST_URL=
RUN if [ -n "$GRADLE_DIST_URL" ]; then \
        sed -i "s|distributionUrl=.*|distributionUrl=${GRADLE_DIST_URL}|" \
            gradle/wrapper/gradle-wrapper.properties; \
    fi

ARG MAVEN_MIRROR=
RUN if [ -n "$MAVEN_MIRROR" ]; then \
        mkdir -p /root/.gradle/init.d && \
        printf 'allprojects {\n    afterEvaluate {\n        repositories.clear()\n        repositories {\n            maven { url = uri("%s") }\n            mavenCentral()\n        }\n    }\n}\n' "$MAVEN_MIRROR" \
            > /root/.gradle/init.d/mirror.gradle; \
    fi

RUN chmod +x gradlew && \
    ./gradlew --no-daemon --console=plain :akiba_mod_utils:moduleJar-AkibaUtils

# The arch identifier is part of the normal import flow now, so it ships with the
# image instead of being something the operator has to build.
RUN ./gradlew --no-daemon --console=plain :akiba_modules:moduleJar-AkibaArch

# The example modules reference each other's jars by file path, so Gradle needs
# those files to exist while it configures the tasks. Seed empty placeholders,
# then build them in dependency order: every real jar replaces its placeholder
# and becomes the classpath entry the next module needs.
RUN mkdir -p subprojects/akiba_mod_example/build/libs && \
    for n in 1 2 3 4 5; do : > subprojects/akiba_mod_example/build/libs/amod-AkibaExample$n-1.0.jar; done && \
    for n in 1 2 3 4 5; do \
        ./gradlew --no-daemon --console=plain :akiba_mod_example:moduleJar-AkibaExample$n || exit 1; \
    done && \
    test -s subprojects/akiba_mod_example/build/libs/amod-AkibaExample5-1.0.jar && \
    test -s subprojects/akiba_mod_utils/build/libs/amod-AkibaUtils-1.2.jar

# ---------------------------------------------------------------------------
# Runtime image
# ---------------------------------------------------------------------------
FROM ubuntu:26.04
ARG VERSION=4.4.0
# Optional: a closer Ubuntu mirror for slow routes to archive.ubuntu.com.
ARG APT_MIRROR=
RUN if [ -n "$APT_MIRROR" ]; then \
        for f in /etc/apt/sources.list /etc/apt/sources.list.d/ubuntu.sources; do \
            [ -f "$f" ] && sed -i "s|http://archive.ubuntu.com/ubuntu|${APT_MIRROR}/ubuntu|g" "$f"; \
        done; \
    fi


RUN apt-get -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::Retries=3 update --fix-missing && \
    apt-get -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::Retries=3 install -y wget gnupg ca-certificates lsb-release

# Optional: a closer PostgreSQL repository (aliyun and tencent both carry it).
ARG PG_MIRROR=
RUN wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O /usr/share/keyrings/postgresql-key.asc && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql-key.asc] ${PG_MIRROR:-http://apt.postgresql.org/pub/repos/apt} $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::Retries=3 update

RUN apt-get -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o Acquire::Retries=3 install -y openjdk-25-jdk wget sudo zip unzip curl nginx pgbackrest postgresql-16 python3-bcrypt vim


RUN curl -fsSL https://nodejs.org/dist/v20.12.2/node-v20.12.2-linux-x64.tar.gz | tar -xz -C /opt && \
    ln -sf /opt/node-v20.12.2-linux-x64 /opt/nodejs && \
    ln -sf /opt/nodejs/bin/node /usr/local/bin/node && \
    ln -sf /opt/nodejs/bin/npm /usr/local/bin/npm && \
    ln -sf /opt/nodejs/bin/npx /usr/local/bin/npx

RUN apt-get clean

RUN useradd -m -s /bin/bash akiba && \
    usermod -aG sudo akiba && \
    echo "akiba ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/akiba && \
    chmod 440 /etc/sudoers.d/akiba && \
    mkdir /akiba && \
    chown akiba:akiba /akiba

USER akiba
WORKDIR /home/akiba

COPY --chown=akiba:akiba subprojects/akiba_frontend /home/akiba/akiba_frontend

# Optional: a closer npm registry, same reason as APT_MIRROR.
ARG NPM_REGISTRY=
RUN if [ -n "$NPM_REGISTRY" ]; then npm config set registry "$NPM_REGISTRY"; fi && \
    cd /home/akiba/akiba_frontend && npm install && npm run build && rm -rf node_modules

COPY --chown=akiba:akiba dockerfile_needed/nginx.conf /etc/nginx/sites-available/akiba_frontend
RUN sudo ln -sf /etc/nginx/sites-available/akiba_frontend /etc/nginx/sites-enabled/ && \
    sudo rm /etc/nginx/sites-enabled/default || true && \
    sudo sed -i 's/user www-data/user akiba/' /etc/nginx/nginx.conf && \
    sudo sed -i 's/#user nobody/user akiba/' /etc/nginx/nginx.conf

COPY --chown=akiba:akiba subprojects/akiba_db_daemon/build/distributions/akiba_db_daemon-${VERSION}.zip .
#RUN wget https://github.com/IoTS-P/Akiba/releases/download/${VERSION}/akiba_db_daemon-${VERSION}.zip
RUN unzip akiba_db_daemon-${VERSION}.zip && \
    rm akiba_db_daemon-${VERSION}.zip && \
    mv akiba_db_daemon-${VERSION} akiba_db_daemon && \
    cd akiba_db_daemon && \
    mkdir /akiba/backups && \
    mkdir /akiba/instances

WORKDIR /home/akiba
COPY --chown=akiba:akiba subprojects/akiba_framework/build/distributions/akiba-${VERSION}.zip .
#RUN wget https://github.com//Akiba/releases/download/${VERSION}/akiba-${VERSION}.zip
RUN unzip akiba-${VERSION}.zip && \
    rm akiba-${VERSION}.zip && \
    mv akiba-${VERSION} akiba_framework && \
    cd akiba_framework

RUN mkdir /home/akiba/binaries
COPY --chown=akiba:akiba dockerfile_needed /home/akiba/binaries
RUN chmod +x /home/akiba/binaries/entrypoint.sh && \
    chmod +x /home/akiba/binaries/test_run.sh && \
    chmod +x /home/akiba/binaries/auto_update.sh && \
    mkdir -p /home/akiba/akiba_framework/modules && \
    mkdir -p /home/akiba/.akiba && \
    echo "${VERSION}" > /home/akiba/.akiba/current_version

# Module jars built by the `modules` stage above (never from the source tree).
COPY --chown=akiba:akiba --from=modules /build/subprojects/akiba_mod_utils/build/libs/amod-*.jar /home/akiba/akiba_framework/modules/
COPY --chown=akiba:akiba --from=modules /build/subprojects/akiba_mod_example/build/libs/amod-*.jar /home/akiba/akiba_framework/modules/
COPY --chown=akiba:akiba --from=modules /build/subprojects/akiba_modules/build/libs/amod-AkibaArch-*.jar /home/akiba/akiba_framework/modules/

WORKDIR /home/akiba/akiba_db_daemon
