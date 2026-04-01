# docker build -t akiba_db_daemon:3.0.1 .

FROM ubuntu:24.04
ARG VERSION=3.1.2

RUN apt-get update --fix-missing
RUN apt-get install -y openjdk-21-jdk wget postgresql-16 pgbackrest sudo zip unzip curl
RUN apt-get clean

RUN useradd -m -s /bin/bash akiba && \
    usermod -aG sudo akiba && \
    echo "akiba ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/akiba && \
    chmod 440 /etc/sudoers.d/akiba && \
    mkdir /akiba && \
    chown akiba:akiba /akiba

USER akiba
WORKDIR /home/akiba

COPY --chown=akiba:akiba subprojects/akiba_db_daemon/build/distributions/akiba_db_daemon-${VERSION}.zip .
#RUN wget https://github.com/IoTS-P/Akiba/releases/download/${VERSION}/akiba_db_daemon-${VERSION}.zip
RUN unzip akiba_db_daemon-${VERSION}.zip && \
    rm akiba_db_daemon-${VERSION}.zip && \
    mv akiba_db_daemon-${VERSION} akiba_db_daemon && \
    cd akiba_db_daemon && \
    mkdir /akiba/backups && \
    mkdir /akiba/instances

WORKDIR /home/akiba
COPY --chown=akiba:akiba subprojects/akiba_framework/build/distributions/akiba_framework-${VERSION}.zip .
#RUN wget https://github.com/IoTS-P/Akiba/releases/download/${VERSION}/akiba_framework-${VERSION}.zip
RUN unzip akiba_framework-${VERSION}.zip && \
    rm akiba_framework-${VERSION}.zip && \
    mv akiba_framework-${VERSION} akiba_framework && \
    cd akiba_framework

RUN mkdir /home/akiba/binaries
COPY --chown=akiba:akiba dockerfile_needed /home/akiba/binaries
RUN chmod +x /home/akiba/binaries/entrypoint.sh
RUN chmod +x /home/akiba/binaries/test_run.sh

WORKDIR /home/akiba/akiba_db_daemon