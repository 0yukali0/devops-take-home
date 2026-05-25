.PHONY: image
image:
	docker build -t beackend:dev .

.PHONY: dev-start
dev-start: dev-stop
	docker compose up -d --build

.PHONY: dev-stop
dev-stop:
	docker compose down