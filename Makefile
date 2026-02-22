# =============================================================================
# vespa-operator-tutorial Makefile
# =============================================================================
# Vespa on Kubernetes（kind）チュートリアル用コマンド集
#
# 基本的な使い方:
#   make all          - クラスター作成から検索まで一括実行
#   make cluster-create  - kind クラスターを作成
#   make deploy       - Vespa をデプロイ
#   make feed         - サンプルデータを投入
#   make search       - 検索テストを実行
#   make clean        - kind クラスターを削除
# =============================================================================

.DEFAULT_GOAL := help
.PHONY: all help setup \
        cluster-create cluster-delete cluster-info \
        deploy deploy-manifests deploy-app \
        wait-ready \
        port-forward stop-port-forward \
        feed search \
        logs status \
        clean

# -----------------------------------------------------------------------------
# 設定変数
# -----------------------------------------------------------------------------
KIND_CLUSTER_NAME  ?= vespa-tutorial
NAMESPACE          ?= vespa
VESPA_ENDPOINT     ?= http://localhost:8080
CONFIG_ENDPOINT    ?= http://localhost:19071
KIND_CONFIG        := k8s/kind/cluster.yaml
K8S_MANIFESTS_DIR  := k8s/vespa
SCRIPTS_DIR        := scripts

# kubectl コンテキスト
KUBECTL_CTX        := kind-$(KIND_CLUSTER_NAME)

# -----------------------------------------------------------------------------
# ターゲット定義
# -----------------------------------------------------------------------------

## 全工程を一括実行（クラスター作成→デプロイ→データ投入→検索）
all: cluster-create deploy wait-ready feed search

## ヘルプを表示
help:
	@echo ""
	@echo "╔══════════════════════════════════════════════════════════════╗"
	@echo "║         vespa-operator-tutorial - 利用可能なコマンド          ║"
	@echo "╚══════════════════════════════════════════════════════════════╝"
	@echo ""
	@echo "【セットアップ】"
	@echo "  make setup            - 依存ツール（kind/kubectl）のインストール確認"
	@echo ""
	@echo "【クラスター管理】"
	@echo "  make cluster-create   - kind クラスターを作成"
	@echo "  make cluster-delete   - kind クラスターを削除"
	@echo "  make cluster-info     - クラスター情報を表示"
	@echo ""
	@echo "【Vespa デプロイ】"
	@echo "  make deploy           - Vespa クラスターをデプロイ（manifests + app）"
	@echo "  make deploy-manifests - Kubernetes マニフェストのみ適用"
	@echo "  make deploy-app       - アプリケーションパッケージのみデプロイ"
	@echo "  make wait-ready       - Vespa の起動を待機"
	@echo ""
	@echo "【アクセス】"
	@echo "  make port-forward     - ポートフォワード開始（バックグラウンド）"
	@echo "  make stop-port-forward - ポートフォワード停止"
	@echo ""
	@echo "【データ操作】"
	@echo "  make feed             - サンプルデータを投入"
	@echo "  make search           - 検索テストを実行"
	@echo ""
	@echo "【モニタリング】"
	@echo "  make logs             - Vespa ポッドのログを表示"
	@echo "  make status           - ポッドとサービスの状態を表示"
	@echo ""
	@echo "【クリーンアップ】"
	@echo "  make clean            - クラスターを削除"
	@echo ""
	@echo "【一括実行】"
	@echo "  make all              - 全工程を一括実行"
	@echo ""

## 依存ツールのインストール確認
setup:
	@echo "=== 依存ツールの確認 ==="
	@command -v kind >/dev/null 2>&1 || \
		(echo "kind がインストールされていません。インストールしてください:" && \
		 echo "  https://kind.sigs.k8s.io/docs/user/quick-start/#installation" && \
		 exit 1)
	@echo "  ✓ kind: $$(kind version)"
	@command -v kubectl >/dev/null 2>&1 || \
		(echo "kubectl がインストールされていません。インストールしてください:" && \
		 echo "  https://kubernetes.io/docs/tasks/tools/" && \
		 exit 1)
	@echo "  ✓ kubectl: $$(kubectl version --client --short 2>/dev/null || kubectl version --client)"
	@command -v docker >/dev/null 2>&1 || \
		(echo "Docker がインストールされていません。インストールしてください:" && \
		 echo "  https://docs.docker.com/get-docker/" && \
		 exit 1)
	@echo "  ✓ docker: $$(docker --version)"
	@echo "=== すべての依存ツールが揃っています ==="

## kind クラスターを作成
cluster-create: setup
	@echo "=== kind クラスターを作成中: $(KIND_CLUSTER_NAME) ==="
	@if kind get clusters 2>/dev/null | grep -q "^$(KIND_CLUSTER_NAME)$$"; then \
		echo "  クラスター $(KIND_CLUSTER_NAME) はすでに存在します"; \
	else \
		kind create cluster --config $(KIND_CONFIG) --name $(KIND_CLUSTER_NAME); \
		echo "  ✓ クラスター作成完了"; \
	fi
	@kubectl config use-context $(KUBECTL_CTX)
	@kubectl cluster-info

## kind クラスターを削除
cluster-delete:
	@echo "=== kind クラスターを削除中: $(KIND_CLUSTER_NAME) ==="
	@kind delete cluster --name $(KIND_CLUSTER_NAME) || true
	@echo "  ✓ クラスター削除完了"

## クラスター情報を表示
cluster-info:
	@kubectl cluster-info --context $(KUBECTL_CTX)
	@echo ""
	@kubectl get nodes --context $(KUBECTL_CTX)

## Kubernetes マニフェストを適用
deploy-manifests:
	@echo "=== Kubernetes マニフェストを適用中 ==="
	@kubectl apply -f $(K8S_MANIFESTS_DIR)/00-namespace.yaml
	@kubectl apply -f $(K8S_MANIFESTS_DIR)/01-configmap-app.yaml
	@kubectl apply -f $(K8S_MANIFESTS_DIR)/02-statefulset.yaml
	@kubectl apply -f $(K8S_MANIFESTS_DIR)/03-service.yaml
	@echo "  ✓ マニフェスト適用完了"
	@echo ""
	@kubectl get pods -n $(NAMESPACE)

## アプリケーションパッケージをデプロイ（Job 実行）
deploy-app:
	@echo "=== アプリケーションパッケージをデプロイ中 ==="
	@# 既存の Job を削除してから再作成
	@kubectl delete job vespa-deploy-app -n $(NAMESPACE) --ignore-not-found
	@kubectl apply -f $(K8S_MANIFESTS_DIR)/04-job-deploy-app.yaml
	@echo "  ✓ デプロイ Job を起動しました"
	@echo "  ログを確認: make logs-deploy"
	@kubectl wait --for=condition=complete job/vespa-deploy-app -n $(NAMESPACE) --timeout=300s
	@echo "  ✓ アプリケーションデプロイ完了"

## Vespa クラスターを完全にデプロイ
deploy: deploy-manifests wait-ready deploy-app
	@echo ""
	@echo "=== Vespa クラスターのデプロイが完了しました ==="
	@echo "  API エンドポイント: $(VESPA_ENDPOINT)"
	@echo ""
	@echo "  次のステップ:"
	@echo "    make feed    - サンプルデータを投入"
	@echo "    make search  - 検索テストを実行"

## Vespa StatefulSet の起動を待機
wait-ready:
	@echo "=== Vespa ポッドの起動を待機中（最大 600秒）... ==="
	@kubectl rollout status statefulset/vespa -n $(NAMESPACE) --timeout=600s
	@echo "  ✓ StatefulSet の起動完了"
	@echo "  コンテナ API の起動を待機中..."
	@$(SCRIPTS_DIR)/wait-for-vespa.sh $(VESPA_ENDPOINT) 300

## ポートフォワードを開始（バックグラウンド）
port-forward:
	@echo "=== ポートフォワードを開始します ==="
	@echo "  コンテナ API: $(VESPA_ENDPOINT)"
	@echo "  コンフィグサーバー: $(CONFIG_ENDPOINT)"
	@kubectl port-forward -n $(NAMESPACE) svc/vespa 8080:8080 19071:19071 &
	@echo "  ✓ ポートフォワード開始（PID: $$!）"
	@echo "  停止するには: make stop-port-forward"

## ポートフォワードを停止
stop-port-forward:
	@echo "=== ポートフォワードを停止します ==="
	@pkill -f "kubectl port-forward.*vespa" || echo "  ポートフォワードプロセスが見つかりません"
	@echo "  ✓ 停止完了"

## サンプルデータを投入
feed:
	@echo "=== サンプルデータを投入します ==="
	@$(SCRIPTS_DIR)/feed-data.sh $(VESPA_ENDPOINT)

## 検索テストを実行
search:
	@echo "=== 検索テストを実行します ==="
	@$(SCRIPTS_DIR)/search.sh $(VESPA_ENDPOINT)

## Vespa ポッドのログを表示
logs:
	@kubectl logs -n $(NAMESPACE) -l app=vespa --tail=100 --all-containers

## デプロイ Job のログを表示
logs-deploy:
	@kubectl logs -n $(NAMESPACE) -l app=vespa-deploy --tail=200

## ポッドとサービスの状態を表示
status:
	@echo "=== Kubernetes リソースの状態 ==="
	@echo ""
	@echo "--- Namespace ---"
	@kubectl get namespace $(NAMESPACE) 2>/dev/null || echo "  Namespace $(NAMESPACE) が見つかりません"
	@echo ""
	@echo "--- Pods ---"
	@kubectl get pods -n $(NAMESPACE) -o wide 2>/dev/null || echo "  ポッドが見つかりません"
	@echo ""
	@echo "--- Services ---"
	@kubectl get services -n $(NAMESPACE) 2>/dev/null || echo "  サービスが見つかりません"
	@echo ""
	@echo "--- StatefulSets ---"
	@kubectl get statefulsets -n $(NAMESPACE) 2>/dev/null || echo "  StatefulSet が見つかりません"
	@echo ""
	@echo "--- PersistentVolumeClaims ---"
	@kubectl get pvc -n $(NAMESPACE) 2>/dev/null || echo "  PVC が見つかりません"

## kind クラスターを削除（クリーンアップ）
clean: cluster-delete
	@echo "=== クリーンアップ完了 ==="
