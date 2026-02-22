# vespa-operator-tutorial

Kubernetes（kind）上で [Vespa](https://vespa.ai/) 検索エンジンのクラスターを構築するチュートリアルです。

[Solr Operator](https://solr.apache.org/operator/) や [Elastic Cloud on Kubernetes (ECK)](https://www.elastic.co/guide/en/cloud-on-k8s/current/index.html) のように、シンプルな設定で冗長化された本格的な検索クラスターを構築することを目標としています。

## 特徴

- **高可用性（HA）構成**: 3ノードクラスター（ZooKeeper クォーラム）、データ冗長化（redundancy=2）
- **日本語対応**: Vespa 組み込みの言語処理により日本語テキストを適切にインデックス
- **kind 対応**: ローカル環境で Docker を使って完全な Kubernetes クラスターを再現
- **Makefile 自動化**: 全操作を `make` コマンドで実行可能

## アーキテクチャ

```
kind クラスター（1 control-plane + 3 workers）
│
└── Namespace: vespa
    │
    ├── StatefulSet: vespa（3 replicas）
    │   ├── vespa-0  ─── コンフィグサーバー + コンテンツノード + コンテナーノード
    │   ├── vespa-1  ─── コンフィグサーバー + コンテンツノード + コンテナーノード
    │   └── vespa-2  ─── コンフィグサーバー + コンテンツノード + コンテナーノード
    │
    ├── Service: vespa-internal（ヘッドレス、ポッド間通信用）
    ├── Service: vespa（NodePort、外部アクセス用）
    │
    └── Job: vespa-deploy-app（アプリパッケージのデプロイ）
```

### 冗長化構成

| コンポーネント | 構成 | 説明 |
|-------------|------|------|
| コンフィグサーバー | 3ノード | ZooKeeper クォーラムで多数決 |
| コンテナーノード | 3ノード | リクエスト振り分け（ラウンドロビン） |
| コンテンツノード | 3ノード、redundancy=2 | データを2ノードに複製 |

1ノードが障害になっても検索・データ保持が継続されます。

## ディレクトリ構成

```
vespa-operator-tutorial/
├── Makefile                    # 全コマンドのエイリアス
├── README.md                   # このファイル
├── .gitignore
├── k8s/
│   ├── kind/
│   │   └── cluster.yaml        # kind クラスター設定（1CP + 3 workers）
│   └── vespa/
│       ├── 00-namespace.yaml   # Namespace 定義
│       ├── 01-configmap-app.yaml  # アプリパッケージ（services.xml + スキーマ）
│       ├── 02-statefulset.yaml # Vespa StatefulSet（HA 構成）
│       ├── 03-service.yaml     # Service（ヘッドレス + NodePort）
│       └── 04-job-deploy-app.yaml # アプリデプロイ Job
├── vespa-app/                  # Vespa アプリケーションパッケージ（参照用）
│   ├── services.xml            # サービス設定（クラスタートポロジー）
│   ├── hosts.xml               # ホストエイリアス定義
│   └── schemas/
│       └── music.sd            # 音楽ドキュメントスキーマ（日本語対応）
├── data/
│   └── sample-music.jsonl      # サンプルデータ（日本語・英語混在）
└── scripts/
    ├── wait-for-vespa.sh       # Vespa 起動待機スクリプト
    ├── feed-data.sh            # データ投入スクリプト
    └── search.sh               # 検索テストスクリプト
```

## 前提条件

以下のツールをインストールしてください。

| ツール | バージョン | インストール方法 |
|--------|-----------|----------------|
| Docker | 20.10+ | https://docs.docker.com/get-docker/ |
| kind   | 0.20+   | https://kind.sigs.k8s.io/docs/user/quick-start/#installation |
| kubectl | 1.28+  | https://kubernetes.io/docs/tasks/tools/ |

```bash
# macOS（Homebrew）
brew install kind kubectl

# Linux
curl -Lo ./kind https://kind.sigs.k8s.io/dl/latest/kind-linux-amd64
chmod +x ./kind && sudo mv ./kind /usr/local/bin/kind
```

## クイックスタート

### 全工程を一括実行

```bash
make all
```

これにより以下が順番に実行されます：
1. kind クラスターの作成
2. Kubernetes マニフェストの適用
3. Vespa 起動待機
4. アプリケーションパッケージのデプロイ
5. サンプルデータの投入
6. 検索テストの実行

### ステップバイステップ実行

#### 1. 依存ツールの確認

```bash
make setup
```

#### 2. kind クラスターの作成

```bash
make cluster-create
```

コントロールプレーン 1台、ワーカー 3台のクラスターが作成されます。

#### 3. Vespa のデプロイ

```bash
make deploy
```

以下が実行されます：
- Kubernetes マニフェストの適用（Namespace、ConfigMap、StatefulSet、Service）
- Vespa 起動待機（最大 600秒）
- アプリケーションパッケージのデプロイ

#### 4. サンプルデータの投入

```bash
make feed
```

`data/sample-music.jsonl` に定義された 15件の音楽データ（日本語・英語混在）を投入します。

#### 5. 検索テスト

```bash
make search
```

以下の検索テストが実行されます：
- 日本語キーワード検索（例：「YOASOBI」）
- 日本語タイトル検索（例：「夜に駆ける」）
- 英語アーティスト検索（例：「Queen」）
- ジャンルフィルター

## 操作コマンド一覧

```bash
make help              # ヘルプを表示
make setup             # 依存ツールの確認
make cluster-create    # kind クラスターを作成
make cluster-delete    # kind クラスターを削除
make cluster-info      # クラスター情報を表示
make deploy            # Vespa を完全デプロイ
make deploy-manifests  # Kubernetes マニフェストのみ適用
make deploy-app        # アプリケーションパッケージのみデプロイ
make wait-ready        # Vespa 起動待機
make port-forward      # ポートフォワード開始
make stop-port-forward # ポートフォワード停止
make feed              # サンプルデータ投入
make search            # 検索テスト実行
make logs              # Vespa ログを表示
make status            # リソース状態を表示
make clean             # クラスターを削除
```

## 手動での API 操作

クラスターが起動したら、直接 API を操作することもできます。

### ポートフォワードの設定

```bash
kubectl port-forward -n vespa svc/vespa 8080:8080 19071:19071
```

### ドキュメントの投入

```bash
curl -X PUT \
  -H "Content-Type: application/json" \
  -d '{"fields": {"title": "夜に駆ける", "artist": "YOASOBI", "year": 2020}}' \
  "http://localhost:8080/document/v1/music/music/docid/1"
```

### 検索クエリ

```bash
# キーワード検索
curl "http://localhost:8080/search/?query=YOASOBI"

# YQL クエリ（ジャンルフィルター）
curl "http://localhost:8080/search/?yql=select%20*%20from%20music%20where%20genre%20contains%20%22J-POP%22"

# 全件取得
curl "http://localhost:8080/search/?yql=select%20*%20from%20music%20where%20true&hits=10"
```

### コンフィグサーバー API

```bash
# デプロイ済みアプリケーションの確認
curl "http://localhost:19071/application/v2/tenant/default/application/"

# クラスター状態の確認
curl "http://localhost:8080/state/v1/health"
```

## Vespa アプリケーションのカスタマイズ

### スキーマの変更

`vespa-app/schemas/music.sd` を編集し、`k8s/vespa/01-configmap-app.yaml` の `music.sd` セクションにも同じ内容を反映してください。

```bash
# スキーマ変更後の再デプロイ
kubectl apply -f k8s/vespa/01-configmap-app.yaml
make deploy-app
```

### ノード数の変更

`k8s/vespa/02-statefulset.yaml` の `replicas` を変更してください。

**注意**: `services.xml` の `<nodes>` 要素も合わせて変更し、`hosts.xml` にも対応するエントリを追加する必要があります。

### 冗長化設定の変更

`k8s/vespa/01-configmap-app.yaml` の `services.xml` 内の `<redundancy>` 値を変更してください。

```xml
<content id="music" version="1.0">
  <redundancy>2</redundancy>  <!-- この値を変更 -->
  ...
</content>
```

**注意**: `redundancy` の値はコンテンツノード数以下である必要があります。

## トラブルシューティング

### ポッドが起動しない

```bash
# ポッドの状態確認
kubectl describe pod -n vespa vespa-0

# ログの確認
kubectl logs -n vespa vespa-0
```

### デプロイ Job が失敗する

```bash
# Job のログ確認
make logs-deploy

# Job を手動で再実行
kubectl delete job vespa-deploy-app -n vespa
kubectl apply -f k8s/vespa/04-job-deploy-app.yaml
```

### メモリ不足エラー

Vespa は多くのメモリを必要とします。Docker Desktop のメモリ割り当てを最低 **8GB** に増やしてください。

```
Docker Desktop > Settings > Resources > Memory: 8GB 以上
```

### kind クラスターのリセット

```bash
make clean
make cluster-create
make deploy
```

## 日本語検索について

Vespa は組み込みの言語処理機能（Linguistics）により、日本語テキストを自動的に適切に処理します。

- **トークナイズ**: Unicode 正規化と文字単位のトークン化
- **BM25 スコアリング**: 日本語テキストにも対応
- **言語自動検出**: `language` フィールドを使ってドキュメントごとに言語を指定可能

より高度な日本語形態素解析が必要な場合は、Vespa の [OpenNLP Linguistics](https://docs.vespa.ai/en/linguistics.html) プラグインの使用を検討してください。

## 参考リンク

- [Vespa 公式ドキュメント](https://docs.vespa.ai/)
- [Vespa GitHub](https://github.com/vespa-engine/vespa)
- [Vespa サンプルアプリ](https://github.com/vespa-engine/sample-apps)
- [kind 公式ドキュメント](https://kind.sigs.k8s.io/)
- [Vespa Docker Hub](https://hub.docker.com/r/vespaengine/vespa)

## ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照してください。