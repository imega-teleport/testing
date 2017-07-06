CON_DIR = build/containers
SRV = data db fileman acceptor
SRV_OBJ = $(addprefix $(CON_DIR)/teleport_,$(SRV))

TELEPORT_DATA_PORT = 6379
TELEPORT_DATA_IP =

test: data_dir $(SRV_OBJ)
	@docker exec teleport_data \
		sh -c 'echo "SET auth:9915e49a-4de1-41aa-9d7d-c9a687ec048d 8c279a62-88de-4d86-9b65-527c81ae767a" | redis-cli --pipe'
	@docker run --rm \
		-v $(CURDIR)/tests:/data \
		--link teleport_acceptor:acceptor \
		alpine sh -c 'apk --upd --no--cache add bash curl zip && /data/simulator1c.sh acceptor "1C+Enterprise/8.3" "9915e49a-4de1-41aa-9d7d-c9a687ec048d:8c279a62-88de-4d86-9b65-527c81ae767a" /data/fixtures/2.04'

discovery_data:
	@while [ "`docker inspect -f {{.State.Running}} teleport_data`" != "true" ]; do \
		echo "wait db"; sleep 0.3; \
	done
	$(eval TELEPORT_DATA_IP = $(shell docker inspect --format '{{ .NetworkSettings.IPAddress }}' teleport_data))

$(CON_DIR)/teleport_data:
	@mkdir -p $(shell dirname $@)
	@docker run -d --name teleport_data -v $(CURDIR)/data:/data imega/redis
	@touch $@

$(CON_DIR)/teleport_db:
	@mkdir -p $(shell dirname $@)
	@docker run -d -p 3306:3306 --name "teleport_db" imega/mysql
	@docker run --rm \
		-v $(CURDIR)/sql:/sql \
		--link teleport_db:s \
		imega/mysql-client \
		mysql --host=s -e "source /sql/schema.sql"
	@touch $@

$(CON_DIR)/teleport_fileman:
	@mkdir -p $(shell dirname $@)
	@docker run -d \
		--name teleport_fileman \
		--link teleport_db:server_db \
		-e DB_HOST=server_db:3306 \
		-v $(CURDIR)/data:/data \
		imegateleport/fileman
	@touch $@

$(CON_DIR)/teleport_acceptor: discovery_data
	@mkdir -p $(shell dirname $@)
	@docker run -d --name teleport_acceptor \
		--env REDIS_IP=$(TELEPORT_DATA_IP) \
		--env REDIS_PORT=$(TELEPORT_DATA_PORT) \
		--link teleport_fileman:fileman \
		-v $(CURDIR)/data:/data \
		imegateleport/bremen
	@touch $@

get_containers:
	$(eval CONTAINERS := $(subst $(CON_DIR)/,,$(shell find $(CON_DIR) -type f)))

stop: get_containers
	@-docker stop $(CONTAINERS)

clean: stop
	@-docker rm -fv $(CONTAINERS)
	@-rm -rf $(CURDIR)/build/*
	@-rm -rf $(CURDIR)/data/*

data_dir:
	@-mkdir -p $(CURDIR)/data/zip $(CURDIR)/data/unzip $(CURDIR)/data/parse $(CURDIR)/data/storage
