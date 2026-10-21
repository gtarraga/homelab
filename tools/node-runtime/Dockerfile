# syntax=docker/dockerfile:1
ARG NODE_IMAGE
ARG APP_IMAGE
FROM ${NODE_IMAGE} AS node
FROM ${APP_IMAGE}
ARG NODE_PATH=/usr/local/bin/node
COPY --from=node /usr/local/bin/node ${NODE_PATH}
RUN --mount=type=bind,source=runtime-check.cjs,target=/tmp/runtime-check.cjs ${NODE_PATH} /tmp/runtime-check.cjs
