# Vespa Operator チュートリアル

Kubernetes 上で [Vespa](https://vespa.ai) 検索エンジンのクラスターを構築するチュートリアルです。  
公式 [`vespaengine/vespa`](https://hub.docker.com/r/vespaengine/vespa) Docker イメージを使用したカスタム Helm チャートにより、冗長化されたマルチノードクラスターを構築します。

## アーキテクチャ概要

```
┌─────────────────────────────────────────────────────────────┐
│ kind クラスター (control-plane × 1 + worker × 4)            │
│                                                             │
│  ┌──────────────────────┐   ┌────────────────────────────┐ │
│  │  コンフィグサーバー   │   │    Vespa サービスノード     │ │
│  │  (StatefulSet × 3)   │   │                            │ │
│  │  ・ZooKeeper クォーラム│   │  フィードコンテナ × 2      │ │
│  │  ・設定管理           │   │  クエリコンテナ × 2        │ │
│  └──────────────────────┘   │  管理ノード × 1            │ │
│                             │  コンテントノード × 2      │ │
│                             │  (冗長度: 2)               │ │
│                             └────────────────────────────┘ │
└─────────────────────────────────────────────────────────────┘
```

| コンポーネント | 役割 | レプリカ数 |
|---|---|---|
| configserver | ZooKeeper クォーラム / 設定管理 | 3 |
| admin | クラスター管理 | 1 |
| feed-container | ドキュメント投入 API | 2 |
| query-container | 検索 API | 2 |
| content | データ保存 / 冗長化 | 2 |

**冗長性**: コンテントノードが 2 台あり `min-redundancy: 2` に設定されているため、1 台のノードが停止してもデータは失われません。

## 前提条件

以下のツールをインストールしてください。

| ツール | バージョン | インストール |
|---|---|---|
| [Docker](https://docs.docker.com/get-docker/) | 20.x 以上 | 公式サイト参照 |
| [kind](https://kind.sigs.k8s.io/docs/user/quick-start/) | 0.20 以上 | `brew install kind` |
| [kubectl](https://kubernetes.io/docs/tasks/tools/) | 1.27 以上 | `brew install kubectl` |
| [Helm](https://helm.sh/docs/intro/install/) | 3.x 以上 | `brew install helm` |
| [Vespa CLI](https://docs.vespa.ai/en/vespa-cli.html) | 8.x 以上 | `brew install vespa-cli` |
| curl, zip, python3 | 標準 | OS 標準 |

> **注意**: このチュートリアルは Docker Desktop が起動している状態で実行してください。  
> ホストマシンに **16GB 以上の RAM** を推奨します（Vespa の各コンポーネントが複数起動するため）。

## クイックスタート

全ステップを一括実行する場合:

```bash
make all
```

ステップバイステップで実行する場合は以下を参照してください。

---

## 詳細手順

### ステップ 1: kind クラスターの作成

```bash
make create-cluster
```

`kind/cluster.yaml` に定義された 4 ワーカーノードの kind クラスターが作成されます。

### ステップ 2: Vespa クラスターのインストール

```bash
make install
```

Helm チャート (`helm/vespa/`) を使って以下のリソースが作成されます:
- ConfigMap (`vespa-config`): `VESPA_CONFIGSERVERS` 環境変数
- ヘッドレスサービス (`vespa-internal`): StatefulSet の Pod DNS 解決用
- フィード/クエリ サービス
- 各コンポーネントの StatefulSet

### ステップ 3: コンフィグサーバーの起動確認

```bash
make wait-configserver
```

コンフィグサーバーは ZooKeeper を使ったクォーラム方式のため、3 台全てが起動する必要があります。  
起動には 2〜5 分ほどかかります。

起動後、健全性を確認:

```bash
make check-configserver-health
```

以下のようなレスポンスが返れば正常です:

```json
{
    "status": {
        "code": "up"
    }
}
```

### ステップ 4: 全 Pod の起動待ち

```bash
make wait-ready
```

全コンポーネントが Ready 状態になるまで待ちます（最大 10 分）。

起動状況の確認:

```bash
make status
```

全 Pod が `Running` または `Ready` 状態になっていることを確認してください:

```
NAME                          READY   STATUS    RESTARTS   AGE
vespa-admin-0                 1/1     Running   0          5m
vespa-configserver-0          1/1     Running   0          8m
vespa-configserver-1          1/1     Running   0          8m
vespa-configserver-2          1/1     Running   0          8m
vespa-content-0               1/1     Running   0          5m
vespa-content-1               1/1     Running   0          5m
vespa-feed-container-0        1/1     Running   0          5m
vespa-feed-container-1        1/1     Running   0          5m
vespa-query-container-0       1/1     Running   0          5m
vespa-query-container-1       1/1     Running   0          5m
```

### ステップ 5: アプリケーションパッケージのデプロイ

```bash
make deploy-app
```

`app/` ディレクトリの内容 (スキーマ定義、サービス設定、ホスト設定) を zip に圧縮し、  
コンフィグサーバーの HTTP API 経由でデプロイします。

成功すると以下のようなレスポンスが返ります:

```json
{
    "message": "Session 5 for tenant 'default' prepared and activated."
}
```

#### アプリケーション構成

| ファイル | 説明 |
|---|---|
| `app/schemas/music.sd` | 音楽ドキュメントスキーマ (日本語 bigram 対応) |
| `app/services.xml` | クラストポロジー定義 |
| `app/hosts.xml` | Pod DNS ↔ ホストエイリアス マッピング |

### ステップ 6: サンプルデータの投入

```bash
make feed
```

`data/feed.json` に含まれる 12 件の音楽データを投入します。  
英語フィールドと日本語フィールドの両方が含まれています。

### ステップ 7: 検索の実行

全ドキュメント検索:

```bash
make search
```

Rock ジャンルの検索:

```bash
make search-rock
```

日本語キーワードで検索 (`ロック` をキーワードに変更することも可能):

```bash
make search-ja
# 別のキーワードを使う場合:
KEYWORD=ビートルズ make search-ja
```

---

## 日本語検索のしくみ

Vespa は標準で日本語形態素解析器を内蔵していませんが、  
**2-gram (bigram) インデックス** を使用することで日本語テキストの検索に対応しています。

```scheme
field title_ja type string {
    indexing: summary | index
    match {
        gram
        gram-size: 2   ← 2文字単位でインデックス化
    }
    index: enable-bm25
}
```

例: `「ロック」` というキーワードは `「ロッ」「ック」` という bigram に分解され、  
`「ロック」` を含む文字列にマッチします。

---

## カスタマイズ

### レプリカ数の変更

`helm/vespa/values.yaml` を編集するか、`--set` フラグで上書きできます:

```bash
# コンテントノードを 3 台に増やす
helm upgrade vespa ./helm/vespa \
    --set content.replicas=3

# クエリコンテナを 3 台に増やす
helm upgrade vespa ./helm/vespa \
    --set queryContainer.replicas=3
```

> **注意**: `content.replicas` を変更した場合は、`app/services.xml` と `app/hosts.xml` も  
> 合わせて更新し、`make deploy-app` を再実行してください。

### 別の名前空間での使用

```bash
make install NAMESPACE=vespa-system
```

> `app/hosts.xml` の `.svc.cluster.local` 前の `default` も変更してください。

### Helm チャートのテンプレート確認

```bash
make helm-template
```

---

## トラブルシューティング

### Pod が起動しない

```bash
# Pod の詳細を確認
kubectl describe pod <pod名>

# ログを確認
kubectl logs <pod名> --tail=100

# init コンテナのログを確認
kubectl logs <pod名> -c chown-var
```

### アプリケーションデプロイが失敗する

コンフィグサーバーの健全性を確認してから再実行してください:

```bash
make check-configserver-health
make deploy-app
```

### 検索結果が 0 件

アプリケーションデプロイ後、サービスの起動に 1〜2 分かかります。  
`make check-health` で全サービスが `"code": "up"` になっていることを確認してください。

---

## クリーンアップ

```bash
# Helm リリースのみ削除 (kind クラスターは残す)
make uninstall

# kind クラスターを含む全リソースを削除
make clean
```

---

## ファイル構成

```
vespa-operator-tutorial/
├── Makefile                   # 全コマンドのエイリアス
├── README.md                  # このファイル
├── .gitignore
├── kind/
│   └── cluster.yaml           # kind クラスター設定 (4 ワーカー)
├── helm/
│   └── vespa/                 # Vespa Helm チャート
│       ├── Chart.yaml
│       ├── values.yaml        # デフォルト設定値
│       └── templates/
│           ├── _helpers.tpl   # テンプレートヘルパー関数
│           ├── configmap.yaml # VESPA_CONFIGSERVERS 設定
│           ├── services.yaml  # ヘッドレス/フィード/クエリ サービス
│           ├── configserver.yaml
│           ├── admin.yaml
│           ├── feed-container.yaml
│           ├── query-container.yaml
│           └── content.yaml
├── app/                       # Vespa アプリケーションパッケージ
│   ├── schemas/
│   │   └── music.sd           # 音楽スキーマ (日本語 bigram 対応)
│   ├── services.xml           # クラストポロジー定義
│   └── hosts.xml              # Pod DNS ↔ ホストエイリアス
└── data/
    └── feed.json              # サンプル音楽データ (日本語対応)
```

---

## 参考資料

- [Vespa 公式ドキュメント](https://docs.vespa.ai/)
- [Vespa Kubernetes ガイド](https://docs.vespa.ai/en/operations/self-managed/using-kubernetes-with-vespa.html)
- [vespa-engine/sample-apps (multinode-HA)](https://github.com/vespa-engine/sample-apps/tree/master/examples/operations/multinode-HA)
- [Vespa スキーマリファレンス](https://docs.vespa.ai/en/reference/schema-reference.html)
- [Vespa YQL クエリ言語](https://docs.vespa.ai/en/query-language.html)
- [kind ドキュメント](https://kind.sigs.k8s.io/)