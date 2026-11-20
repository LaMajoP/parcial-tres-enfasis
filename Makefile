.PHONY: setup dev seed build lint test test-integration test-e2e test-all terraform-validate kind-up kind-down demo-success demo-fail-billing demo-fail-charger demo-canary

setup:
	npm run setup
dev:
	npm run dev
seed:
	npm run seed
build:
	npm run build
lint:
	npm run lint
test:
	npm test
test-integration:
	npm run test:integration
test-e2e:
	npm run test:e2e
test-all:
	npm run test:all
terraform-validate:
	npm run terraform:validate
kind-up:
	npm run kind:up
kind-down:
	npm run kind:down
demo-success:
	npm run demo:success
demo-fail-billing:
	npm run demo:fail-billing
demo-fail-charger:
	npm run demo:fail-charger
demo-canary:
	npm run demo:canary
