SYSTEMD_DIR := /etc/systemd/system
SERVICES    := llama llama-embedding searxng openwebui qdrant qdrant-mcp monitoring

.PHONY: install start stop

install:
	sudo mkdir -p /data/persistence/openwebui /data/persistence/qdrant
	docker network create ai-stack 2>/dev/null || true
	for svc in $(SERVICES); do \
		sudo cp $(CURDIR)/services/$${svc}/$${svc}.service $(SYSTEMD_DIR)/$${svc}.service; \
	done
	sudo systemctl daemon-reload
	sudo systemctl enable $(SERVICES)

start:
	sudo systemctl start $(SERVICES)

stop:
	sudo systemctl stop $(SERVICES)
