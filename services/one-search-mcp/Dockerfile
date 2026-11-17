ARG ONESEARCH_VERSION=1.2.4
ARG MCP_PROXY_VERSION=0.15.0

FROM ghcr.io/yokingma/one-search-mcp:${ONESEARCH_VERSION}

USER root

# uv static binary — no apt, no system python needed
COPY --from=ghcr.io/astral-sh/uv:0.13.9 /uv /usr/local/bin/uv

ENV UV_TOOL_BIN_DIR=/usr/local/bin \
    UV_TOOL_DIR=/opt/uv-tools \
    UV_PYTHON_INSTALL_DIR=/opt/uv-python

ARG MCP_PROXY_VERSION
# mcp-proxy caps mcp<2 itself since 0.13.0 (mcp 2.x dropped the request_ctx var it imports).
RUN uv tool install --python 3.12 mcp-proxy==${MCP_PROXY_VERSION} \
 && chmod -R a+rX /opt/uv-tools /opt/uv-python

# one-search-mcp's own browser-detection (agent-browser's findBrowser()) only checks
# hardcoded system paths (/usr/bin/chromium, /usr/bin/google-chrome, ...), which don't
# exist on this Playwright base image - Chromium lives under /ms-playwright instead.
# That miss is caught internally and it still launches fine via Playwright's own
# executable-path auto-detection, but every scrape/search call logs a scary "Cannot
# find a supported browser" error. Symlink the real binary into the path it expects so
# detection succeeds and the log noise goes away. Resolved via `find` (not hardcoded to
# e.g. chromium-1208) so this survives the base image bumping its bundled Chromium build.
RUN ln -s "$(find /ms-playwright -maxdepth 2 -type d -name 'chromium-*' ! -name '*headless*' | head -1)/chrome-linux64/chrome" /usr/bin/chromium

USER pwuser
EXPOSE 3002

# Standalone default. one-search-mcp.service overrides CMD to add --allowed-host entries:
# since 0.13.3 mcp-proxy rejects Host headers other than loopback names, so the nginx
# vhost domain (from Kconfig) has to be allowlisted at runtime.
ENTRYPOINT ["mcp-proxy"]
CMD ["--host=0.0.0.0", "--port=3002", "--pass-environment", \
     "--allow-origin=*", "--", "node", "/app/dist/index.js"]
