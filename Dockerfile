# syntax=docker/dockerfile:1.7

ARG RUBY_VERSION=3.3.4

FROM ruby:${RUBY_VERSION}-slim AS runtime

ARG APP_HOME=/app
ARG WORKSPACE_DIR=/workspace
ARG BUILD_DATE=unknown
ARG VCS_REF=unknown
ARG VERSION=dev

ENV APP_HOME=${APP_HOME} \
    WORKSPACE_DIR=${WORKSPACE_DIR} \
    HOME=/home/app \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

LABEL org.opencontainers.image.title="GitLab CI SSDLC Auditor" \
      org.opencontainers.image.description="Static SSDLC auditor for GitLab CI pipelines" \
      org.opencontainers.image.url="https://github.com/polishyankee/Gitlab-CI-Auditor" \
      org.opencontainers.image.documentation="https://github.com/polishyankee/Gitlab-CI-Auditor#readme" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.source="https://github.com/polishyankee/Gitlab-CI-Auditor"

WORKDIR ${APP_HOME}

RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates tzdata \
    && gem install --no-document webrick \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --system --gid 10001 app \
    && useradd --system --uid 10001 --gid 10001 --create-home --home-dir /home/app app \
    && mkdir -p ${WORKSPACE_DIR} \
    && chown -R app:app ${APP_HOME} ${WORKSPACE_DIR}

COPY --chown=app:app bin/ ./bin/
COPY --chown=app:app config/ ./config/
COPY --chown=app:app examples/ ./examples/
COPY --chown=app:app lib/ ./lib/
COPY --chown=app:app templates/ ./templates/
COPY --chown=app:app README.md ROADMAP.md RULES.md BACKLOG.md CONTRIBUTING.md ./

RUN chmod +x ./bin/gitlab-ci-auditor

USER app

EXPOSE 4567

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD ruby -r net/http -e 'response = Net::HTTP.get_response(URI("http://127.0.0.1:4567/")); exit(response.is_a?(Net::HTTPSuccess) ? 0 : 1)'

ENTRYPOINT ["./bin/gitlab-ci-auditor"]
CMD ["serve", "--host", "0.0.0.0", "--port", "4567"]
