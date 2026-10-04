SHELL        := /bin/bash
.ONESHELL:
# Needed so the unit pattern rule can use the stem twice ($$*/$$*.service) —
# plain pattern prerequisites only substitute the first '%'.
.SECONDEXPANSION:

PREFIX                       ?=
CONF_DEST                    := $(PREFIX)/etc/ai-stack/ai-stack.conf
SYSTEMD_DIR                  := $(PREFIX)/etc/systemd/system
NFTABLES_SRC                 := nftables.conf
NFTABLES_DEST                := $(PREFIX)/etc/nftables.conf
SYSLOG_NG_CONF_D_SRC         := syslog-ng/conf.d
SYSLOG_NG_CONF_D_DEST        := $(PREFIX)/etc/syslog-ng/conf.d
LOGROTATE_SRC                := nginx/logrotate.d/ai-stack.conf
LOGROTATE_DEST                := $(PREFIX)/etc/logrotate.d/ai-stack
BASE_DIR                     := $(shell pwd)
NETWORK_NAME                 := ai-stack
KCONFIG                      := $(BASE_DIR)/Kconfig
DOTCONFIG                    := $(BASE_DIR)/.config

SERVICES := llama searxng openwebui one-search-mcp \
            node-exporter amd-device-metrics grafana-mcp
UNIT_TARGETS      := $(addprefix $(SYSTEMD_DIR)/,$(addsuffix .service,$(SERVICES)))
INSTALL_TARGETS   := $(addprefix install-,$(SERVICES))
UNINSTALL_TARGETS := $(addprefix uninstall-,$(SERVICES))
BUILD_IMAGES      := llama one-search-mcp
BUILD_TARGETS     := $(addprefix build-,$(BUILD_IMAGES))
INSTALL_BUILD_TARGETS   := $(addprefix install-,$(BUILD_IMAGES))
INSTALL_NOBUILD_TARGETS := $(filter-out $(INSTALL_BUILD_TARGETS),$(INSTALL_TARGETS))

.PHONY: help menuconfig config service install $(INSTALL_TARGETS) \
        uninstall $(UNINSTALL_TARGETS) install-nginx uninstall-nginx \
        install-syslog-ng uninstall-syslog-ng install-logrotate uninstall-logrotate \
        firewall network build $(BUILD_TARGETS) start-all stop-all restart-all

help:
	@echo "Usage: make <target>"
	echo ""
	echo "Setup:"
	echo "  menuconfig  Choose parameters via a curses menu, write $(DOTCONFIG) (run as your normal user)"
	echo "  config      Translate $(DOTCONFIG) into $(CONF_DEST), create data dirs (run as root)"
	echo "  network     Create the external ai-stack Docker network"
	echo "  build       Build the two locally-built images (llama, one-search-mcp)"
	echo "  build-<name>  Build just one of them"
	echo "  service     Render and install all standalone systemd unit files from $(CONF_DEST)"
	echo "  install     Run network then service"
	for svc in $(SERVICES); do echo "  install-$$svc  Run network then install just the $$svc.service unit"; done
	echo "  uninstall   Disable and remove all systemd units, config file, and network"
	for svc in $(SERVICES); do echo "  uninstall-$$svc  Disable and remove just the $$svc.service unit"; done
	echo "  install-nginx  Copy nginx.conf and symlink sites-available into /etc/nginx/servers"
	echo "  uninstall-nginx  Remove nginx.conf copy and symlinks from /etc/nginx/servers"
	echo "  install-syslog-ng  Copy syslog-ng drop-in configs to /etc/syslog-ng/conf.d and reload"
	echo "  uninstall-syslog-ng  Remove syslog-ng drop-in configs and reload"
	echo "  install-logrotate  Copy nginx log rotation config to /etc/logrotate.d"
	echo "  uninstall-logrotate  Remove nginx log rotation config"
	echo "  firewall    Render and apply nftables rules (requires config)"
	echo ""
	echo "Operations:"
	echo "  start-all   Start all $(words $(SERVICES)) standalone systemd units"
	echo "  stop-all    Stop all $(words $(SERVICES)) standalone systemd units"
	echo "  restart-all Restart all $(words $(SERVICES)) standalone systemd units"
	echo ""
	echo "Use systemctl/journalctl directly to manage individual units."

menuconfig:
	@set -euo pipefail
	command -v menuconfig >/dev/null || { echo "Error: menuconfig not found. Install with: sudo pacman -S python-kconfiglib"; exit 1; }
	"$(BASE_DIR)/scripts/gen-gpu-kconfig.sh" > "$(BASE_DIR)/Kconfig.gpus"
	BASE_DIR="$(BASE_DIR)" KCONFIG_CONFIG="$(DOTCONFIG)" menuconfig "$(KCONFIG)"

$(CONF_DEST): $(DOTCONFIG) Makefile
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make config)"; exit 1; }
	[[ -f "$(DOTCONFIG)" ]] || { echo "Error: $(DOTCONFIG) not found — run 'make menuconfig' first (as your normal user)"; exit 1; }

	set -a; source "$(DOTCONFIG)"; set +a

	SYSTEM_USER="$$CONFIG_SYSTEM_USER"
	if ! id -u "$$SYSTEM_USER" &>/dev/null; then
		read -rp "User '$$SYSTEM_USER' does not exist — create it? [y/N]: " yn
		[[ "$$yn" =~ ^[Yy] ]] || { echo "Aborted."; exit 1; }
		useradd -s /sbin/nologin "$$SYSTEM_USER"
	fi
	SYSTEM_UID=$$(id -u "$$SYSTEM_USER")
	SYSTEM_GID=$$(id -g "$$SYSTEM_USER")
	VIDEO_GID=$$(getent group video | cut -d: -f3)
	RENDER_GID=$$(getent group render | cut -d: -f3)
	[[ -n "$$VIDEO_GID" ]] || { echo "Error: 'video' group not found"; exit 1; }
	[[ -n "$$RENDER_GID" ]] || { echo "Error: 'render' group not found"; exit 1; }
	getent group docker >/dev/null || { echo "Error: 'docker' group not found"; exit 1; }

	# Every unit invokes docker as $SYSTEM_USER (systemd User=/Group=); llama also
	# needs video/render on the host to access /dev/kfd,/dev/dri themselves (the containers get
	# GPU access via --group-add instead, using the numeric GIDs captured above).
	usermod -aG docker,video,render "$$SYSTEM_USER"
	echo "Added '$$SYSTEM_USER' to docker, video, render (a running session for that user won't"
	echo "see this until it logs in again; systemd units read group membership fresh each start)"

	DATA_DIR="$$CONFIG_DATA_DIR"

	# Checked GPUs are CONFIG_GPU_DEVICE_<UPPERCASE UUID HEX>=y (see scripts/gen-gpu-kconfig.sh).
	GPUS=()
	for var in $$(compgen -v CONFIG_GPU_DEVICE_); do
		if [[ "$${!var}" == y ]]; then hex="$${var#CONFIG_GPU_DEVICE_}"; GPUS+=("GPU-$${hex,,}"); fi
	done
	IFS=',' read -ra EXTRA <<< "$${CONFIG_GPU_DEVICES_EXTRA:-}"
	GPUS+=("$${EXTRA[@]}")
	GPU_DEVICES=$$(IFS=,; echo "$${GPUS[*]}")
	[[ -n "$$GPU_DEVICES" ]] || { echo "Error: no GPU selected — check one in 'make menuconfig' (llama menu)"; exit 1; }

	# Sanity-check GPU UUIDs against rocminfo when it's available (indices are passed as-is).
	if command -v rocminfo >/dev/null; then
		KNOWN=$$(rocminfo 2>/dev/null | awk '/^ *Uuid:/ {print $$2}')
		for g in "$${GPUS[@]}"; do
			[[ "$$g" == GPU-* ]] || continue
			grep -qx "$$g" <<< "$$KNOWN" || echo "WARNING: GPU_DEVICES entry '$$g' not reported by rocminfo (known: $$(tr '\n' ' ' <<< "$$KNOWN"))"
		done
	fi

	mkdir -p "$(PREFIX)/etc/ai-stack"
	{
			echo "PUID=$$SYSTEM_UID"
			echo "PGID=$$SYSTEM_GID"
			echo "VIDEO_GID=$$VIDEO_GID"
			echo "RENDER_GID=$$RENDER_GID"
			echo "BASE_DIR=$(BASE_DIR)"
			echo "DATA_DIR=$$DATA_DIR"
			echo "MODELS_DIR=$$CONFIG_MODELS_DIR"
			echo "GPU_DEVICES=$$GPU_DEVICES"
			echo "BIND_HOST=$$CONFIG_BIND_HOST"
			echo "DNS_SERVERS=$$CONFIG_DNS_SERVERS"
			echo "SEARXNG_SECRET=$$CONFIG_SEARXNG_SECRET"
			echo "GRAFANA_URL=$$CONFIG_GRAFANA_URL"
			echo "GRAFANA_SERVICE_ACCOUNT_TOKEN=$$CONFIG_GRAFANA_SERVICE_ACCOUNT_TOKEN"
			echo "MCP_GRAFANA_SERVER_TOKEN=$$CONFIG_GRAFANA_MCP_SERVER_TOKEN"
			echo "LLAMA_VERSION=$$CONFIG_LLAMA_VERSION"
			echo "LLAMA_PORT=$$CONFIG_LLAMA_PORT"
			echo "LLAMA_DOMAIN=$$CONFIG_LLAMA_DOMAIN"
			echo "SEARXNG_PORT=$$CONFIG_SEARXNG_PORT"
			echo "SEARXNG_DOMAIN=$$CONFIG_SEARXNG_DOMAIN"
			echo "OPENWEBUI_PORT=$$CONFIG_OPENWEBUI_PORT"
			echo "OPENWEBUI_DOMAIN=$$CONFIG_OPENWEBUI_DOMAIN"
			echo "ONESEARCH_MCP_PORT=$$CONFIG_ONESEARCH_MCP_PORT"
			echo "ONESEARCH_MCP_DOMAIN=$$CONFIG_ONESEARCH_MCP_DOMAIN"
			echo "GRAFANA_MCP_PORT=$$CONFIG_GRAFANA_MCP_PORT"
			echo "GRAFANA_MCP_DOMAIN=$$CONFIG_GRAFANA_MCP_DOMAIN"
		} > "$(CONF_DEST)"
	chmod 600 "$(CONF_DEST)"
	chown "$$SYSTEM_UID:$$SYSTEM_GID" "$(CONF_DEST)"
	echo "Config written: $(CONF_DEST)"

	mkdir -p "$$DATA_DIR/openwebui"
	chown -R "$$SYSTEM_UID:$$SYSTEM_GID" "$$DATA_DIR"
	echo "Directories created and ownership set"

config: $(CONF_DEST)

network:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make network)"; exit 1; }
	docker network inspect $(NETWORK_NAME) >/dev/null 2>&1 || docker network create $(NETWORK_NAME)
	echo "Docker network '$(NETWORK_NAME)' ready"

$(SYSTEMD_DIR)/%.service: services/$$*/$$*.service $(CONF_DEST)
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make service)"; exit 1; }

	mkdir -p "$(SYSTEMD_DIR)"
	set -a; source "$(CONF_DEST)"; set +a
	export CONF_DEST="$(CONF_DEST)"
	envsubst < "$(BASE_DIR)/services/$*/$*.service" > "$(SYSTEMD_DIR)/$*.service"
	chown "$$PUID:$$PGID" "$(SYSTEMD_DIR)/$*.service"
	systemctl daemon-reload
	echo "Unit installed: $(SYSTEMD_DIR)/$*.service"
	echo "Next: sudo systemctl enable --now $*.service"

service: $(UNIT_TARGETS)

install: network build $(UNIT_TARGETS)

$(INSTALL_BUILD_TARGETS): install-%: network build-% $(SYSTEMD_DIR)/%.service

$(INSTALL_NOBUILD_TARGETS): install-%: network $(SYSTEMD_DIR)/%.service

install-nginx:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make install-nginx)"; exit 1; }
	[[ -f "$(CONF_DEST)" ]] || { echo "Error: $(CONF_DEST) not found — run 'sudo make config' first"; exit 1; }
	mkdir -p "$(PREFIX)/etc/nginx/servers"
	cp "$(BASE_DIR)/nginx/nginx.conf" "$(PREFIX)/etc/nginx/nginx.conf"
	echo "Copied: $(PREFIX)/etc/nginx/nginx.conf"
	set -a; source "$(CONF_DEST)"; set +a
	# Restrict envsubst to just the domain vars below — an unrestricted pass would also try to
	# substitute nginx's OWN $host/$remote_addr/$scheme/... (same $NAME syntax) with nothing.
	for conf in "$(BASE_DIR)/nginx/sites-available/"*; do
		envsubst '$$LLAMA_DOMAIN,$$SEARXNG_DOMAIN,$$OPENWEBUI_DOMAIN,$$ONESEARCH_MCP_DOMAIN,$$GRAFANA_MCP_DOMAIN' \
			< "$$conf" > "$(PREFIX)/etc/nginx/servers/$$(basename $$conf)"
		echo "Rendered: $(PREFIX)/etc/nginx/servers/$$(basename $$conf)"
	done
	nginx -t && systemctl reload nginx
	echo "Nginx reloaded"

uninstall-nginx:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make uninstall-nginx)"; exit 1; }
	rm -f "$(PREFIX)/etc/nginx/nginx.conf"
	echo "Removed: $(PREFIX)/etc/nginx/nginx.conf"
	for conf in "$(BASE_DIR)/nginx/sites-available/"*; do
		rm -f "$(PREFIX)/etc/nginx/servers/$$(basename $$conf)"
		echo "Removed: $(PREFIX)/etc/nginx/servers/$$(basename $$conf)"
	done
	nginx -t && systemctl reload nginx
	echo "Nginx reloaded"

install-syslog-ng:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make install-syslog-ng)"; exit 1; }
	mkdir -p "$(SYSLOG_NG_CONF_D_DEST)"
	cp "$(BASE_DIR)/$(SYSLOG_NG_CONF_D_SRC)/"*.conf "$(SYSLOG_NG_CONF_D_DEST)/"
	syslog-ng --syntax-only
	systemctl reload syslog-ng@default.service
	echo "syslog-ng configs installed: $(SYSLOG_NG_CONF_D_DEST)"
	echo "Next: sudo systemctl enable --now syslog-ng"

uninstall-syslog-ng:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make uninstall-syslog-ng)"; exit 1; }
	rm -f "$(SYSLOG_NG_CONF_D_DEST)/10-common.conf" \
	      "$(SYSLOG_NG_CONF_D_DEST)/20-nginx-access.conf" \
	      "$(SYSLOG_NG_CONF_D_DEST)/20-nginx-error.conf" \
	      "$(SYSLOG_NG_CONF_D_DEST)/20-systemd-units.conf"
	systemctl reload syslog-ng
	echo "syslog-ng configs removed"

install-logrotate:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make install-logrotate)"; exit 1; }
	mkdir -p "$(PREFIX)/etc/logrotate.d"
	cp "$(BASE_DIR)/$(LOGROTATE_SRC)" "$(LOGROTATE_DEST)"
	echo "Installed: $(LOGROTATE_DEST)"

uninstall-logrotate:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make uninstall-logrotate)"; exit 1; }
	rm -f "$(LOGROTATE_DEST)"
	echo "Removed: $(LOGROTATE_DEST)"

firewall:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make firewall)"; exit 1; }
	DETECTED=$$(ip route | awk '/^default/ {print $$5; exit}')
	read -rp "Network interface [$${DETECTED:-none detected}]: " IFACE
	IFACE=$${IFACE:-$$DETECTED}
	[[ -n "$$IFACE" ]] || { echo "Error: no network interface specified"; exit 1; }
	export IFACE
	envsubst '$$IFACE' < "$(BASE_DIR)/$(NFTABLES_SRC)" > "$(NFTABLES_DEST)"
	nft -f "$(NFTABLES_DEST)"
	systemctl enable nftables
	systemctl restart nftables
	echo "Firewall rules applied: $(NFTABLES_DEST)"

build: $(BUILD_TARGETS)

build-llama:
	@set -euo pipefail
	[[ -f "$(DOTCONFIG)" ]] || { echo "Error: $(DOTCONFIG) not found — run 'make menuconfig' first"; exit 1; }
	set -a; source "$(DOTCONFIG)"; set +a
	SYSTEM_UID=$$(id -u "$$CONFIG_SYSTEM_USER")
	SYSTEM_GID=$$(id -g "$$CONFIG_SYSTEM_USER")
	[[ -n "$${CONFIG_LLAMA_GPU_TARGETS:-}" ]] || { echo "Error: LLAMA_GPU_TARGETS is empty — set it in 'make menuconfig' (llama menu)"; exit 1; }
	docker build \
		--build-arg LLAMA_VERSION="$$CONFIG_LLAMA_VERSION" \
		--build-arg GPU_TARGETS="$$CONFIG_LLAMA_GPU_TARGETS" \
		--build-arg AI_UID="$$SYSTEM_UID" \
		--build-arg AI_GID="$$SYSTEM_GID" \
		-t llama-cpp-rocm:latest \
		"$(BASE_DIR)/services/llama"
	echo "Built: llama-cpp-rocm:latest"

build-one-search-mcp:
	@set -euo pipefail
	docker build -t one-search-mcp-proxy:latest "$(BASE_DIR)/services/one-search-mcp"
	echo "Built: one-search-mcp-proxy:latest"

uninstall:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make uninstall)"; exit 1; }
	for svc in $(SERVICES); do systemctl disable --now "$$svc.service" 2>/dev/null || true; done
	rm -f $(UNIT_TARGETS)
	systemctl daemon-reload
	rm -f "$(CONF_DEST)"
	rmdir --ignore-fail-on-non-empty "$(PREFIX)/etc/ai-stack" 2>/dev/null || true
	docker network rm $(NETWORK_NAME) 2>/dev/null || true
	echo "Uninstalled"

$(UNINSTALL_TARGETS): uninstall-%:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make uninstall-$*)"; exit 1; }
	systemctl disable --now "$*.service" 2>/dev/null || true
	rm -f "$(SYSTEMD_DIR)/$*.service"
	systemctl daemon-reload
	echo "Uninstalled $*.service"

start-all:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make start-all)"; exit 1; }
	systemctl start $(SERVICES)
	echo "Started: $(SERVICES)"

enable-all:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make enable-all)"; exit 1; }
	systemctl enable $(SERVICES)
	echo "Started: $(SERVICES)"

disable-all:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make disable-all)"; exit 1; }
	systemctl disable $(SERVICES)
	echo "Started: $(SERVICES)"

stop-all:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make stop-all)"; exit 1; }
	systemctl stop $(SERVICES)
	echo "Stopped: $(SERVICES)"

restart-all:
	@set -euo pipefail
	[[ "$$(id -u)" -eq 0 ]] || { echo "Error: run as root (sudo make restart-all)"; exit 1; }
	systemctl restart $(SERVICES)
	echo "Restarted: $(SERVICES)"
