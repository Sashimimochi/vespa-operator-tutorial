# =============================================================================
# Vespa on Kubernetes (kind) チュートリアル Makefile
# =============================================================================
# 使い方 / Usage:
#   make help          — コマンド一覧を表示 / Show available commands
#   make all           — クラスター構築からデータ投入まで一括実行 / Full setup
#   make clean         — 全リソースを削除 / Delete all resources
# =============================================================================

# --- 設定変数 / Configuration variables ---
CLUSTER_NAME    := vespa
NAMESPACE       := default
HELM_RELEASE    := vespa
HELM_CHART      := ./helm/vespa

# Pod / Service 名 (Helm リリース名 + コンポーネント名)
CONFIGSERVER_POD  := $(HELM_RELEASE)-configserver-0
FEED_SVC          := $(HELM_RELEASE)-feed
QUERY_SVC         := $(HELM_RELEASE)-query

# ポート番号 / Port numbers
CONFIG_PORT  := 19071
FEED_PORT    := 8080
QUERY_PORT   := 8081

# アプリケーションパッケージ / Application package
APP_DIR  := ./app
APP_ZIP  := /tmp/vespa-app.zip

# ポートフォワード管理ファイル / Port-forward management files
PORT_FORWARD_PID_FILE ?= .port-forward.pid
PORT_FORWARD_LOG_FILE ?= .port-forward.log

# --- ヘルパー / Helpers ---
BOLD  := \033[1m
RESET := \033[0m
GREEN := \033[32m
BLUE  := \033[34m

.DEFAULT_GOAL := help

# =============================================================================
# ヘルプ / Help
# =============================================================================
.PHONY: help
help: ## コマンド一覧 / Show available commands
	@echo ""
	@echo "$(BOLD)Vespa on Kubernetes (kind) チュートリアル$(RESET)"
	@echo "=============================================="
	@echo ""
	@echo "$(BOLD)クイックスタート / Quick start:$(RESET)"
	@echo "  make all          — 全ステップを順番に実行 / Run all steps in order"
	@echo ""
	@echo "$(BOLD)個別コマンド / Individual commands:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-22s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(BOLD)前提条件 / Prerequisites:$(RESET)"
	@echo "  - Docker, kind, kubectl, helm, vespa, curl, zip がインストール済みであること"
	@echo "  - Docker daemon が起動していること"
	@echo ""

# =============================================================================
# 全ステップ一括実行 / Run all steps
# =============================================================================
.PHONY: all
all: create-cluster install wait-configserver start-services deploy-app wait-ready wait-app port-forward feed ## 全ステップを順番に実行 / Run full setup end to end

# =============================================================================
# 1. kind クラスター作成 / Create kind cluster
# =============================================================================
.PHONY: create-cluster
create-cluster: ## kind クラスターを作成する / Create kind cluster
	@echo "$(BLUE)>>> kind クラスター '$(CLUSTER_NAME)' を作成しています...$(RESET)"
	kind create cluster --name $(CLUSTER_NAME) --config kind/cluster.yaml
	@echo "$(GREEN)>>> kind クラスターの作成が完了しました$(RESET)"

# =============================================================================
# 2. Helm で Vespa をインストール / Install Vespa via Helm
# =============================================================================
.PHONY: install
install: ## Helm で Vespa クラスターをインストールする / Install Vespa cluster via Helm
	@echo "$(BLUE)>>> Vespa クラスターを Helm でインストールしています...$(RESET)"
	helm install $(HELM_RELEASE) $(HELM_CHART) \
		--namespace $(NAMESPACE) \
		--create-namespace
	@echo "$(GREEN)>>> Helm インストールが完了しました$(RESET)"
	@echo "Pod の起動状況を確認するには: make status"

# =============================================================================
# 共通: Helm テンプレートから XML を生成 / Generate XML from Helm templates (shared)
# =============================================================================
.PHONY: generate-app-xml
generate-app-xml: ## Helm テンプレートから services.xml / hosts.xml を生成する / Generate app XMLs from Helm templates
	@echo "$(BLUE)>>> Helm テンプレートから services.xml / hosts.xml を生成しています...$(RESET)" && \
	TMPFILE=$$(mktemp) && \
	helm template $(HELM_RELEASE) $(HELM_CHART) \
		--namespace $(NAMESPACE) \
		--show-only templates/vespa-app-configmap.yaml \
		> $$TMPFILE && \
	awk '/^  services[.]xml: [|]/{f=1;next} /^  [^ ]/{f=0} f{sub(/^    /,""); print}' \
		$$TMPFILE > $(APP_DIR)/services.xml && \
	awk '/^  hosts[.]xml: [|]/{f=1;next} /^  [^ ]/{f=0} f{sub(/^    /,""); print}' \
		$$TMPFILE > $(APP_DIR)/hosts.xml && \
	rm -f $$TMPFILE && \
	echo "$(GREEN)>>> services.xml / hosts.xml の生成が完了しました$(RESET)"

# =============================================================================
# 3. コンフィグサーバーの起動待ち / Wait for config servers
# =============================================================================
.PHONY: wait-configserver
wait-configserver: ## コンフィグサーバーの起動を待つ / Wait for config servers to be ready
	@echo "$(BLUE)>>> Pod の起動を待っています (60 秒)...$(RESET)"
	@sleep 60
	@echo "$(BLUE)>>> 全コンフィグサーバー Pod (3 台) の Ready を待っています (最大 8 分)...$(RESET)"
	kubectl wait pod \
		-l app=$(HELM_RELEASE)-configserver \
		--for=condition=Ready \
		--timeout=480s \
		--namespace=$(NAMESPACE)
	@echo "$(GREEN)>>> 全コンフィグサーバー Pod が Ready になりました$(RESET)"
	@echo "$(BLUE)>>> コンフィグサーバー HTTP API (port 19071) の応答を待っています (最大 5 分)...$(RESET)"
	@for i in $$(seq 1 30); do \
		STATUS=$$(kubectl exec $(CONFIGSERVER_POD) --namespace=$(NAMESPACE) -- \
			curl -sf http://localhost:19071/state/v1/health 2>/dev/null | \
			python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',{}).get('code','unknown'))" 2>/dev/null); \
		echo "コンフィグサーバー状態: $${STATUS:-unknown} (試行 $$i/30)"; \
		if [ "$$STATUS" = "up" ]; then \
			echo "$(GREEN)>>> コンフィグサーバーが起動しました$(RESET)"; \
			exit 0; \
		fi; \
		if [ $$i -eq 30 ]; then echo "タイムアウト: コンフィグサーバーが応答しません"; exit 1; fi; \
		sleep 10; \
	done

# =============================================================================
# 4. その他のサービス (必要に応じて手動で実行) / Start additional services
# =============================================================================
.PHONY: start-services
start-services: ## 全サービスの起動確認をする / Verify all service pods are starting
	@echo "$(BLUE)>>> 全 Pod の起動状況:$(RESET)"
	kubectl get pods --namespace=$(NAMESPACE)

# =============================================================================
# 5. 全 Pod が Ready になるまで待つ / Wait for all pods to be ready
# =============================================================================
.PHONY: wait-ready
wait-ready: ## 全 Pod が Ready になるまで待つ / Wait for all pods to be Ready
	@echo "$(BLUE)>>> 全 Pod の Ready 状態を待っています (最大 10 分)...$(RESET)"
	kubectl wait pods \
		--all \
		--for=condition=Ready \
		--timeout=600s \
		--namespace=$(NAMESPACE)
	@echo "$(GREEN)>>> 全 Pod が Ready 状態になりました$(RESET)"

# =============================================================================
# 共通: StatefulSet ロールアウト待機 / Wait for StatefulSet rollouts (shared)
# =============================================================================
.PHONY: wait-rollout
wait-rollout: ## 各 StatefulSet のロールアウト完了を待つ / Wait for StatefulSet rollouts to complete
	@echo "$(BLUE)>>> StatefulSet のロールアウト完了を待っています (最大 10 分)...$(RESET)"
	@kubectl rollout status statefulset/$(HELM_RELEASE)-configserver \
		--namespace=$(NAMESPACE) --timeout=600s || true
	@kubectl rollout status statefulset/$(HELM_RELEASE)-admin \
		--namespace=$(NAMESPACE) --timeout=600s || true
	@kubectl rollout status statefulset/$(HELM_RELEASE)-feed-container \
		--namespace=$(NAMESPACE) --timeout=600s || true
	@kubectl rollout status statefulset/$(HELM_RELEASE)-query-container \
		--namespace=$(NAMESPACE) --timeout=600s || true
	@kubectl rollout status statefulset/$(HELM_RELEASE)-content \
		--namespace=$(NAMESPACE) --timeout=600s || true
	@echo "$(GREEN)>>> 全 StatefulSet のロールアウトが完了しました$(RESET)"

# =============================================================================
# 6. Vespa アプリケーションのデプロイ / Deploy Vespa application
# =============================================================================
.PHONY: deploy-app
deploy-app: generate-app-xml ## Vespa アプリケーションパッケージをデプロイする / Deploy Vespa application package
	@echo "$(BLUE)>>> アプリケーションパッケージを zip に圧縮しています...$(RESET)" && \
	cd $(APP_DIR) && zip -r $(APP_ZIP) . -x "*.DS_Store" && \
	echo "$(BLUE)>>> コンフィグサーバーへポートフォワードを開始します...$(RESET)"; \
	kubectl port-forward pod/$(CONFIGSERVER_POD) $(CONFIG_PORT):19071 --namespace=$(NAMESPACE) & \
	PF_PID=$$!; \
	sleep 5; \
	echo "$(BLUE)>>> アプリケーションをデプロイしています...$(RESET)"; \
	DEPLOY_STATUS=1; \
	for i in $$(seq 1 5); do \
		RESULT=$$(curl --silent --show-error \
			--header "Content-Type: application/zip" \
			--data-binary @$(APP_ZIP) \
			http://localhost:$(CONFIG_PORT)/application/v2/tenant/default/prepareandactivate 2>&1); \
		CURL_STATUS=$$?; \
		if [ $$CURL_STATUS -eq 0 ] && echo "$$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'session' in str(d) or 'log' in str(d) else 1)" 2>/dev/null; then \
			echo "$$RESULT" | python3 -m json.tool 2>/dev/null || echo "$$RESULT"; \
			DEPLOY_STATUS=0; \
			break; \
		fi; \
		echo "デプロイ試行 $$i/5 失敗 (curl exit: $$CURL_STATUS)、10 秒後に再試行..."; \
		echo "$$RESULT" | python3 -m json.tool 2>/dev/null || echo "$$RESULT"; \
		sleep 10; \
	done; \
	kill $$PF_PID 2>/dev/null || true; \
	rm -f $(APP_ZIP); \
	if [ $$DEPLOY_STATUS -eq 0 ]; then \
		echo "$(GREEN)>>> アプリケーションのデプロイが完了しました$(RESET)"; \
	else \
		echo "デプロイ失敗。make check-configserver-health で状態を確認してください。"; \
	fi; \
	exit $$DEPLOY_STATUS

# =============================================================================
# スケール / Scale (無停止レプリカ数変更 / Zero-downtime replica count change)
# =============================================================================
# 使い方 / Usage:
#   values.yaml でレプリカ数を変更後に実行してください
#   Edit replica counts in values.yaml, then run:
#     make scale
# 実行順序 / Execution order:
#   1. Helm テンプレートから新 services.xml / hosts.xml を生成して Vespa へデプロイ (無停止)
#   2. Vespa がコンフィグを反映するまで 30 秒待機
#   3. helm upgrade で Kubernetes StatefulSet をスケール
#   4. 各 StatefulSet のロールアウト完了待ち
# =============================================================================
.PHONY: scale
scale: deploy-app ## values.yaml のレプリカ数変更を無停止で反映する / Apply replica changes zero-downtime
	@echo "$(BLUE)>>> [2/4] Vespa がコンフィグを反映するまで待っています (30 秒)...$(RESET)"
	@sleep 30
	@echo "$(BLUE)>>> [3/4] Kubernetes マニフェストを適用しています (helm upgrade)...$(RESET)"
	helm upgrade $(HELM_RELEASE) $(HELM_CHART) --namespace $(NAMESPACE)
	@echo "$(GREEN)>>> helm upgrade が完了しました$(RESET)"
	@$(MAKE) wait-rollout
	@echo "$(GREEN)>>> スケール完了。make status で Pod の状態を確認してください$(RESET)"

# =============================================================================
# 7. アプリケーション起動待ち / Wait for app to be ready
# =============================================================================
.PHONY: wait-app
wait-app: ## アプリケーション起動後の健全性チェックを待つ / Wait for application health
	@echo "$(BLUE)>>> アプリケーションの起動を待っています (60 秒)...$(RESET)"
	@sleep 60
	@echo "$(BLUE)>>> フィードコンテナの健全性を確認しています...$(RESET)"; \
	kubectl port-forward svc/$(FEED_SVC) 18080:8080 --namespace=$(NAMESPACE) & \
	PF_PID=$$!; \
	sleep 5; \
	for i in $$(seq 1 12); do \
		STATUS=$$(curl -s http://localhost:18080/state/v1/health | \
			python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('status',{}).get('code','unknown'))" 2>/dev/null); \
		echo "フィードコンテナ状態: $$STATUS (試行 $$i/12)"; \
		if [ "$$STATUS" = "up" ]; then \
			echo "$(GREEN)>>> フィードコンテナが起動しました$(RESET)"; \
			kill $$PF_PID 2>/dev/null || true; \
			sleep 3; \
			exit 0; \
		fi; \
		sleep 10; \
	done; \
	kill $$PF_PID 2>/dev/null || true; \
	sleep 3; \
	echo "タイムアウト: フィードコンテナがまだ起動中の可能性があります。make check-health で再確認してください。 / Timeout: Feed container may still be starting. Re-check with: make check-health"

# =============================================================================
# データ投入 / Feed data
# =============================================================================
.PHONY: feed
feed: ## サンプルデータを Vespa に投入する / Feed sample data to Vespa
	@echo "$(BLUE)>>> サンプルデータを投入しています...$(RESET)"; \
	kubectl port-forward svc/$(FEED_SVC) $(FEED_PORT):8080 --namespace=$(NAMESPACE) & \
	PF_PID=$$!; \
	sleep 5; \
	vespa feed --target http://localhost:$(FEED_PORT) data/feed.json; \
	FEED_STATUS=$$?; \
	kill $$PF_PID 2>/dev/null || true; \
	if [ $$FEED_STATUS -eq 0 ]; then \
		echo "$(GREEN)>>> データ投入が完了しました$(RESET)"; \
	else \
		echo "データ投入に失敗したドキュメントがあります。make status で状態を確認してください。"; \
		exit 1; \
	fi

# =============================================================================
# 検索 / Search
# =============================================================================
.PHONY: search
search: ## 全ドキュメントを検索する / Search all documents
	@echo "$(BLUE)>>> 全ドキュメントを検索しています...$(RESET)"; \
	kubectl port-forward svc/$(QUERY_SVC) $(QUERY_PORT):8080 --namespace=$(NAMESPACE) & \
	PF_PID=$$!; \
	sleep 5; \
	curl -s \
		"http://localhost:$(QUERY_PORT)/search/?yql=select+*+from+music+where+true&hits=20" | \
		python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin), ensure_ascii=False, indent=2))"; \
	kill $$PF_PID 2>/dev/null || true

.PHONY: search-rock
search-rock: ## "Rock" ジャンルを検索する / Search Rock genre
	@echo "$(BLUE)>>> Rock ジャンルを検索しています...$(RESET)"; \
	kubectl port-forward svc/$(QUERY_SVC) $(QUERY_PORT):8080 --namespace=$(NAMESPACE) & \
	PF_PID=$$!; \
	sleep 5; \
	curl -s \
		"http://localhost:$(QUERY_PORT)/search/?yql=select+*+from+music+where+genre+contains+%22Rock%22&hits=10" | \
		python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin), ensure_ascii=False, indent=2))"; \
	kill $$PF_PID 2>/dev/null || true

.PHONY: search-ja
search-ja: ## 日本語キーワードで検索する (例: ロック) / Search with Japanese keyword (e.g. ロック)
	@echo "$(BLUE)>>> 日本語検索: '$${KEYWORD:-ロック}'$(RESET)"; \
	kubectl port-forward svc/$(QUERY_SVC) $(QUERY_PORT):8080 --namespace=$(NAMESPACE) & \
	PF_PID=$$!; \
	sleep 5; \
	KEYWORD=$${KEYWORD:-ロック}; \
	curl -s --data-urlencode "yql=select * from music where title_ja contains \"$$KEYWORD\" or album_ja contains \"$$KEYWORD\"" \
		--data-urlencode "hits=10" \
		"http://localhost:$(QUERY_PORT)/search/" | \
		python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin), ensure_ascii=False, indent=2))"; \
	kill $$PF_PID 2>/dev/null || true

.PHONY: port-forward
port-forward: ## バックグラウンドでポートフォワードを開始する (自動再起動付き) / Start background port-forward with auto-restart
	@if [ -f "$(PORT_FORWARD_PID_FILE)" ] && ps -p "$$(cat "$(PORT_FORWARD_PID_FILE)")" >/dev/null 2>&1; then \
		echo "ポートフォワードは既に起動中です (pid=$$(cat "$(PORT_FORWARD_PID_FILE)"))"; \
		exit 0; \
	fi
	@rm -f "$(PORT_FORWARD_LOG_FILE)"
	@( while true; do \
		kubectl port-forward pod/$(CONFIGSERVER_POD) $(CONFIG_PORT):19071 --namespace=$(NAMESPACE) >> "$(PORT_FORWARD_LOG_FILE)" 2>&1 & \
		PF1=$$!; \
		kubectl port-forward svc/$(FEED_SVC) $(FEED_PORT):8080 --namespace=$(NAMESPACE) >> "$(PORT_FORWARD_LOG_FILE)" 2>&1 & \
		PF2=$$!; \
		kubectl port-forward svc/$(QUERY_SVC) $(QUERY_PORT):8080 --namespace=$(NAMESPACE) >> "$(PORT_FORWARD_LOG_FILE)" 2>&1 & \
		PF3=$$!; \
		wait $$PF1 $$PF2 $$PF3; \
		echo "[port-forward] 再起動中 (3 秒後)..." >> "$(PORT_FORWARD_LOG_FILE)"; \
		sleep 3; \
	done ) & echo $$! > "$(PORT_FORWARD_PID_FILE)"
	@sleep 3
	@echo "$(GREEN)>>> ポートフォワード (自動再起動) を開始しました (pid=$$(cat "$(PORT_FORWARD_PID_FILE)"), log=$(PORT_FORWARD_LOG_FILE))$(RESET)"
	@echo "  config: localhost:$(CONFIG_PORT) -> configserver:19071"
	@echo "  feed  : localhost:$(FEED_PORT)   -> feed:8080"
	@echo "  query : localhost:$(QUERY_PORT)  -> query:8080"

.PHONY: stop-port-forward
stop-port-forward: ## バックグラウンドのポートフォワードを停止する / Stop background port-forward
	@if [ -f "$(PORT_FORWARD_PID_FILE)" ]; then \
		PID=$$(cat "$(PORT_FORWARD_PID_FILE)"); \
		if ps -p "$$PID" >/dev/null 2>&1; then \
			pkill -P "$$PID" 2>/dev/null || true; \
			kill "$$PID" 2>/dev/null || true; \
			echo "ポートフォワードを停止しました (pid=$$PID)"; \
		else \
			echo "ポートフォワードは起動していません"; \
		fi; \
		rm -f "$(PORT_FORWARD_PID_FILE)"; \
	else \
		echo "ポートフォワードは起動していません"; \
	fi

# =============================================================================
# ユーティリティ / Utilities
# =============================================================================
.PHONY: status
status: ## Pod の起動状況を確認する / Show pod status
	@echo "$(BOLD)Pod 一覧:$(RESET)"
	kubectl get pods --namespace=$(NAMESPACE) -o wide
	@echo ""
	@echo "$(BOLD)Service 一覧:$(RESET)"
	kubectl get services --namespace=$(NAMESPACE)

.PHONY: check-configserver-health
check-configserver-health: ## コンフィグサーバーの健全性を確認する / Check config server health
	@echo "$(BLUE)>>> コンフィグサーバーの健全性を確認しています...$(RESET)"; \
	kubectl port-forward pod/$(CONFIGSERVER_POD) $(CONFIG_PORT):19071 --namespace=$(NAMESPACE) & \
	PF_PID=$$!; \
	sleep 5; \
	curl -s http://localhost:$(CONFIG_PORT)/state/v1/health | python3 -m json.tool; \
	kill $$PF_PID 2>/dev/null || true

.PHONY: check-health
check-health: ## 全サービスの健全性を確認する / Check health of all services
	@echo "$(BOLD)=== コンフィグサーバー健全性 ===$(RESET)"; \
	kubectl port-forward pod/$(CONFIGSERVER_POD) $(CONFIG_PORT):19071 --namespace=$(NAMESPACE) & \
	PF1=$$!; sleep 5; \
	curl -s http://localhost:$(CONFIG_PORT)/state/v1/health | python3 -m json.tool; \
	kill $$PF1 2>/dev/null || true
	@echo "" && echo "$(BOLD)=== フィードコンテナ健全性 ===$(RESET)"; \
	kubectl port-forward svc/$(FEED_SVC) $(FEED_PORT):8080 --namespace=$(NAMESPACE) & \
	PF2=$$!; sleep 5; \
	curl -s http://localhost:$(FEED_PORT)/state/v1/health | python3 -m json.tool; \
	kill $$PF2 2>/dev/null || true
	@echo "" && echo "$(BOLD)=== クエリコンテナ健全性 ===$(RESET)"; \
	kubectl port-forward svc/$(QUERY_SVC) $(QUERY_PORT):8080 --namespace=$(NAMESPACE) & \
	PF3=$$!; sleep 5; \
	curl -s http://localhost:$(QUERY_PORT)/state/v1/health | python3 -m json.tool; \
	kill $$PF3 2>/dev/null || true

.PHONY: logs
logs: ## コンポーネントのログを表示する (COMPONENT=<pod名> で指定) / Show logs (COMPONENT=<podname>)
	kubectl logs $(COMPONENT) --namespace=$(NAMESPACE) --tail=100

.PHONY: port-forward-config
port-forward-config: ## コンフィグサーバーへのポートフォワードを開始 / Start port-forward to config server
	@echo "$(BLUE)>>> ポートフォワード: localhost:$(CONFIG_PORT) -> configserver:19071$(RESET)"
	@echo "  Ctrl+C で停止できます / Press Ctrl+C to stop"
	kubectl port-forward pod/$(CONFIGSERVER_POD) $(CONFIG_PORT):19071 --namespace=$(NAMESPACE)

.PHONY: port-forward-feed
port-forward-feed: ## フィードエンドポイントへのポートフォワードを開始 / Start port-forward to feed endpoint
	@echo "$(BLUE)>>> ポートフォワード: localhost:$(FEED_PORT) -> feed:8080$(RESET)"
	@echo "  Ctrl+C で停止できます / Press Ctrl+C to stop"
	kubectl port-forward svc/$(FEED_SVC) $(FEED_PORT):8080 --namespace=$(NAMESPACE)

.PHONY: port-forward-query
port-forward-query: ## クエリエンドポイントへのポートフォワードを開始 / Start port-forward to query endpoint
	@echo "$(BLUE)>>> ポートフォワード: localhost:$(QUERY_PORT) -> query:8080$(RESET)"
	@echo "  Ctrl+C で停止できます / Press Ctrl+C to stop"
	kubectl port-forward svc/$(QUERY_SVC) $(QUERY_PORT):8080 --namespace=$(NAMESPACE)

# =============================================================================
# クリーンアップ / Cleanup
# =============================================================================
.PHONY: uninstall
uninstall: ## Vespa の Helm リリースを削除する / Uninstall Vespa Helm release
	@echo "$(BLUE)>>> Vespa Helm リリースを削除しています...$(RESET)"
	helm uninstall $(HELM_RELEASE) --namespace=$(NAMESPACE)
	@echo "$(BLUE)>>> PVC を削除しています...$(RESET)"
	kubectl delete pvc --all --namespace=$(NAMESPACE) --ignore-not-found=true

.PHONY: clean
clean: stop-port-forward ## kind クラスターを含む全リソースを削除する / Delete all resources including kind cluster
	@echo "$(BLUE)>>> 全リソースを削除しています...$(RESET)"
	-helm uninstall $(HELM_RELEASE) --namespace=$(NAMESPACE) 2>/dev/null || true
	-kubectl delete pvc --all --namespace=$(NAMESPACE) 2>/dev/null || true
	kind delete cluster --name $(CLUSTER_NAME)
	@echo "$(GREEN)>>> クリーンアップ完了$(RESET)"

.PHONY: helm-lint
helm-lint: ## Helm チャートの構文チェック / Lint the Helm chart
	helm lint $(HELM_CHART)

.PHONY: helm-template
helm-template: ## Helm テンプレートをレンダリングして確認する / Render Helm templates for review
	helm template $(HELM_RELEASE) $(HELM_CHART) --namespace=$(NAMESPACE)
