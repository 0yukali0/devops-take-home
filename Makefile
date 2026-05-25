.PHONY: image
image:
	make -C backend image

.PHONY: dev-start
dev-start:
	make -C backend dev-start

.PHONY: dev-stop
dev-stop:
	make -C backend dev-stop

.PHONY: devbox-start
devbox-start:
	make -C docker cluster-start
	make -C charts obs-deploy

.PHONY: devbox-stop
devbox-stop:
	make -C docker cluster-stop