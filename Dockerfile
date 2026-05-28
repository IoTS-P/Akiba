# docker build -t akiba_allinone:3.2.0 .

FROM ubuntu:24.04
ARG VERSION=3.2.0

RUN apt-get update --fix-missing && \
    apt-get install -y wget gnupg ca-certificates lsb-release

RUN wget -q https://www.postgresql.org/media/keys/ACCC4CF8.asc -O /usr/share/keyrings/postgresql-key.asc && \
    echo "deb [signed-by=/usr/share/keyrings/postgresql-key.asc] http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list && \
    apt-get update

RUN apt-get install -y openjdk-21-jdk wget sudo zip unzip curl nginx pgbackrest postgresql-16 python3-bcrypt

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
#RUN wget https://github.com//Akiba/releases/download/${VERSION}/akiba_framework-${VERSION}.zip
RUN unzip akiba-${VERSION}.zip && \
    rm akiba-${VERSION}.zip && \
    mv akiba-${VERSION} akiba_framework && \
    cd akiba_framework

RUN mkdir /home/akiba/binaries
COPY --chown=akiba:akiba dockerfile_needed /home/akiba/binaries
RUN chmod +x /home/akiba/binaries/entrypoint.sh && \
    chmod +x /home/akiba/binaries/test_run.sh && \
    chmod +x /home/akiba/binaries/init_akiba.sh && \
    mkdir -p /home/akiba/akiba_framework/modules && \
    cp /home/akiba/binaries/amod*.jar /home/akiba/akiba_framework/modules/

COPY --chown=akiba:akiba subprojects/akiba_frontend /home/akiba/akiba_frontend

RUN cd /home/akiba/akiba_frontend && npm install && npm run build && rm -rf node_modules

COPY --chown=akiba:akiba dockerfile_needed/nginx.conf /etc/nginx/sites-available/akiba_frontend
RUN sudo ln -sf /etc/nginx/sites-available/akiba_frontend /etc/nginx/sites-enabled/ && \
    sudo rm /etc/nginx/sites-enabled/default || true && \
    sudo sed -i 's/user www-data/user akiba/' /etc/nginx/nginx.conf && \
    sudo sed -i 's/#user nobody/user akiba/' /etc/nginx/nginx.conf

WORKDIR /home/akiba/akiba_db_daemon
