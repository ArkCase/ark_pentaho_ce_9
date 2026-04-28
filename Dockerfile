###########################################################################################################
#
# How to build:
#
# docker build -t arkcase/pentaho-ce:latest .
#
###########################################################################################################

ARG PUBLIC_REGISTRY="public.ecr.aws"
ARG PRIVATE_REGISTRY
ARG VER="9.4.0.0"
ARG JAVA="11"

ARG PENTAHO_VERSION="${VER}-343"
ARG LB_VER="4.20.0"
ARG LB_SRC="https://github.com/liquibase/liquibase/releases/download/v${LB_VER}/liquibase-${LB_VER}.tar.gz"
ARG CW_VER="1.8.0"
ARG CW_REPO="https://nexus.armedia.com/repository/arkcase"
ARG CW_SRC="com.armedia.acm:curator-wrapper:${CW_VER}:jar:exe"

ARG BASE_REGISTRY="${PUBLIC_REGISTRY}"
ARG BASE_REPO="arkcase/base-java"
ARG BASE_VER="24.04"
ARG BASE_VER_PFX=""
ARG BASE_IMG="${BASE_REGISTRY}/${BASE_REPO}:${BASE_VER_PFX}${BASE_VER}"

ARG PENTAHO_INSTALL_REPO="arkcase/pentaho-ce-${VER%%.*}-install"
ARG PENTAHO_INSTALL_IMG="${PRIVATE_REGISTRY}/${PENTAHO_INSTALL_REPO}:${BASE_VER_PFX}${VER}"

ARG TOMCAT_REGISTRY="${BASE_REGISTRY}"
ARG TOMCAT_REPO="arkcase/base-tomcat"
ARG TOMCAT_VER="latest"
ARG TOMCAT_VER_PFX="${BASE_VER_PFX}"
ARG TOMCAT_IMG="${TOMCAT_REGISTRY}/${TOMCAT_REPO}:${TOMCAT_VER_PFX}${TOMCAT_VER}"

FROM "${PENTAHO_INSTALL_IMG}" AS src

ARG TOMCAT_IMG

FROM "${TOMCAT_IMG}" AS tomcat

ARG BASE_IMG

FROM "${BASE_IMG}"

ARG VER
ARG JAVA
ARG LB_SRC
ARG CW_REPO
ARG CW_SRC
ARG PENTAHO_VERSION

ARG PENTAHO_PORT="8080"
ENV PENTAHO_USER="pentaho"
ENV PENTAHO_UID="1998"
ENV PENTAHO_GROUP="${PENTAHO_USER}"
ENV PENTAHO_GID="${PENTAHO_UID}"

ENV WORK_DIR="${DATA_DIR}/work"
ENV TEMP_DIR="${DATA_DIR}/temp"
ENV HOME_DIR="${BASE_DIR}/${PENTAHO_USER}"
ENV LB_DIR="${BASE_DIR}/lb"
ENV LB_TAR="${BASE_DIR}/lb.tar.gz"

ENV PENTAHO_HOME="${HOME_DIR}"
ENV PENTAHO_PDI_HOME="${BASE_DIR}/pentaho-pdi"
ENV PENTAHO_PDI_LIB="${PENTAHO_PDI_HOME}/data-integration/lib"
ENV PENTAHO_SERVER="${PENTAHO_HOME}/pentaho-server"
ENV PENTAHO_TOMCAT="${PENTAHO_SERVER}/tomcat"
ENV PENTAHO_WEBAPP="${PENTAHO_TOMCAT}/webapps/pentaho"
ENV PENTAHO_VERSION="${PENTAHO_VERSION}"

LABEL ORG="Armedia LLC" \
      APP="Pentaho EE" \
      VERSION="${VER}" \
      IMAGE_SOURCE="https://github.com/ArkCase/ark_pentaho_ee" \
      MAINTAINER="Armedia Devops Team <devops@armedia.com>"

RUN mkdir -p "${BASE_DIR}" && \
    chmod "u=rwx,go=rx" "${BASE_DIR}" && \
    groupadd --system --gid "${PENTAHO_GID}" "${PENTAHO_GROUP}" && \
    useradd --system --uid "${PENTAHO_UID}" --gid "${PENTAHO_GID}" --groups "${ACM_GROUP}" --create-home --home-dir "${PENTAHO_HOME}" "${PENTAHO_USER}" 

#
# Make sure the user's HOME envvar points to the right place
#
ENV HOME="${PENTAHO_HOME}"

COPY --from=src --chown=${PENTAHO_USER}:${PENTAHO_GROUP} /home/pentaho/app/pentaho "${PENTAHO_HOME}/"
COPY --from=src --chown=${PENTAHO_USER}:${PENTAHO_GROUP} /home/pentaho/app/pentaho-pdi "${PENTAHO_PDI_HOME}/"

RUN set-java "${JAVA}" && \
    apt-get -y install \
        cron \
        libapr1 \
      && \
    apt-get clean

ENV PATH="${PENTAHO_SERVER}:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ENV LD_LIBRARY_PATH="${PENTAHO_TOMCAT}/lib"

COPY entrypoint /

COPY --chown=${PENTAHO_USER}:${PENTAHO_GROUP} --chmod=0640 "server.xml" "logging.properties" "catalina.properties" "${PENTAHO_TOMCAT}/conf/"
COPY --chown=${PENTAHO_USER}:${PENTAHO_GROUP} --chmod=0750 start-pentaho.sh "${PENTAHO_SERVER}/"
COPY --chown=${PENTAHO_USER}:${PENTAHO_GROUP} --chmod=0640 repository.spring.xml "${PENTAHO_SERVER}/pentaho-solutions/system/"
RUN chown -R "${PENTAHO_UID}:${PENTAHO_GID}" "${BASE_DIR}"/* && \
    chmod -R "u=rwX,g=rX,o=" "${BASE_DIR}"/* && \
    chown "${PENTAHO_USER}:${PENTAHO_GROUP}" "${PENTAHO_TOMCAT}/conf"/* && \
    chmod "u=rwX,go=r" "${PENTAHO_TOMCAT}/conf"/* && \
    rm -f "${PENTAHO_SERVER}/promptuser.sh" "${PENTAHO_SERVER}"/*.bat "${PENTAHO_SERVER}"/*.js && \
    chmod "u=rwX,g=rX,o=" "${PENTAHO_SERVER}"/*.sh  && \
    find "${PENTAHO_HOME}" -mindepth 1 -maxdepth 1 -type f -name '.*' -exec chmod "u=rwX,g=r,o=" "{}" ";" && \
    chown root "${PENTAHO_SERVER}"

# Install Liquibase, and add all the drivers
RUN umask 0027 && \
    curl -L --fail -o "${LB_TAR}" "${LB_SRC}" && \
    mkdir -p "${LB_DIR}" && \
    tar -C "${LB_DIR}" -xzvf "${LB_TAR}" && \
    rm -rf "${LB_TAR}" && \
    cd "${LB_DIR}" && \
    rm -fv \
        "internal/lib/mssql-jdbc.jar" \
        "internal/lib/ojdbc8.jar" \
        "internal/lib/mariadb-java-client.jar" \
        "internal/lib/postgresql.jar" \
      && \
    ln -sv \
        "${PENTAHO_TOMCAT}/lib"/mysql-connector-j-*.jar \
        "${PENTAHO_TOMCAT}/lib"/mysql-legacy-driver-*.jar \
        "${PENTAHO_TOMCAT}/lib"/mariadb-java-client-*.jar \
        "${PENTAHO_TOMCAT}/lib"/mssql-jdbc-*.jar \
        "${PENTAHO_TOMCAT}/lib"/ojdbc11-*.jar \
        "${PENTAHO_TOMCAT}/lib"/postgresql-*.jar \
        "internal/lib"

COPY --chown=${PENTAHO_USER}:${PENTAHO_GROUP} liquibase.properties "${LB_DIR}/"
COPY --chown=${PENTAHO_USER}:${PENTAHO_GROUP} "sql/${PENTAHO_VERSION}" "${LB_DIR}/pentaho/"
RUN chown -R "${PENTAHO_USER}:${PENTAHO_GROUP}" "${LB_DIR}" && \
    chmod -R "o=" "${LB_DIR}"

RUN mvn-get "${CW_SRC}" "${CW_REPO}" "/usr/local/bin/curator-wrapper.jar"

COPY --from=tomcat --chmod=0755 /usr/local/bin/set-session-cookie-name /usr/local/bin/

# Set cron SUID so we can run it as non-root
RUN chmod ug+s /usr/sbin/cron

RUN mkdir -p "${HOME_DIR}/.postgresql" && \
    ln -svf "${CA_TRUSTS_PEM}" "${HOME_DIR}/.postgresql/root.crt" && \
    chown -Rh "${PENTAHO_USER}:${PENTAHO_GROUP}" "${HOME_DIR}/.postgresql" && \
    chmod -R "u=rwX,g=rX,o=" "${HOME_DIR}/.postgresql"

USER "${PENTAHO_USER}"

VOLUME [ "${DATA_DIR}" ]
VOLUME [ "${LOGS_DIR}" ]

EXPOSE "${PENTAHO_PORT}"
WORKDIR "${PENTAHO_SERVER}"
ENTRYPOINT [ "/entrypoint" ]
