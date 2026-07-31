# AWS 3層構成 Terraform テンプレート（監視・WAF対応）

AWS上に **WAF・ALB を含む3層構成（Web / App / DB）** を、Terraform（IaC）で構築するコードです。ネットワーク・サーバー・データベース・ロードバランサーに加え、**CloudWatch による監視通知**と **WAF による攻撃防御・ログ収集**までを、Terraformでコード化しています。

本リポジトリは、[CloudFormation版](https://github.com/ogihara-v/aws-study-cloudformation)で構築した構成を、同一の設計思想のままTerraformで再現したものです。2つのIaCツールでの実装経験を積むことを目的としています。

---

## 構成図（通信の流れ）

```
インターネット
    │  HTTP(80)
    ▼
  WAF（WebACL / AWSマネージドルール）  … ALBに関連付け
    │
    ▼
  ALB（Application Load Balancer）   … パブリックサブネット(1a/1c)
    │  HTTP(8080)
    ▼
  EC2（Amazon Linux 2023 / Webサーバー）  … パブリックサブネット(1a)
    │  MySQL(3306)
    ▼
  RDS（MySQL）  … プライベートサブネット(1a/1c)
```

監視・ログの流れ

```
EC2 ──CPU使用率──▶ CloudWatch Alarm ──▶ SNS Topic ──▶ メール通知
WAF ──検査ログ────▶ CloudWatch Logs（aws-waf-logs-study / 保持7日）
```

---

## ファイル構成

```
.
├── main.tf              # 全リソースの定義（ネットワーク〜WAFまで、層ごとに区切り）
├── variables.tf          # 変数の宣言（型・説明・デフォルト値）
├── outputs.tf            # apply後に表示される出力値（ALB DNS名、RDSエンドポイント等）
├── terraform.tfvars      # 変数の実際の値（Git管理対象外、各自で作成）
├── .gitignore             # tfvars・stateファイル等を除外
└── README.md
```

---

## 作成されるリソース

| 分類 | Terraformリソース | 説明 |
|---|---|---|
| ネットワーク | `aws_vpc` | 10.0.0.0/16 |
| | `aws_subnet` ×4 | パブリック(1a/1c)・プライベート(1a/1c) |
| | `aws_internet_gateway` | 外部との出入口（VPCへの紐付けも同時に完結） |
| | `aws_route_table` / `aws_route_table_association` | 0.0.0.0/0 → IGW |
| セキュリティ | `aws_security_group`（ALB用） | インターネットから 80 を許可 |
| | `aws_security_group`（EC2用） | ALBのSGからの 8080、管理者IPからの SSH 22 を許可 |
| | `aws_security_group`（RDS用） | EC2のSGからの 3306 を許可 |
| アプリ | `aws_instance` | t2.micro / Amazon Linux 2023（`data "aws_ami"`で最新AMIを動的取得） |
| ロードバランサー | `aws_alb` / `aws_lb_target_group` / `aws_lb_target_group_attachment` / `aws_lb_listener` | HTTP、ヘルスチェック付き |
| データベース | `aws_db_subnet_group` / `aws_db_instance` | MySQL / db.t4g.micro / プライベート配置 |
| 監視・通知 | `aws_sns_topic` / `aws_sns_topic_subscription` | アラーム通知の宛先（メール購読） |
| | `aws_cloudwatch_metric_alarm` | EC2のCPU使用率を監視し、閾値超過でSNSへ通知 |
| セキュリティ(WAF) | `aws_wafv2_web_acl` | AWSマネージドルール（Core rule set）を適用 |
| | `aws_cloudwatch_log_group` | WAFの検査ログを保存（保持7日） |
| | `aws_wafv2_web_acl_logging_configuration` | WebACL とロググループを紐付け |
| | `aws_wafv2_web_acl_association` | WAFをALBに関連付け |

---

## セキュリティ設計

### ネットワーク層（最小権限のSG連鎖）

各層のセキュリティグループを分離し、「1つ前のリソースからのみ許可」する連鎖構成にしています。

- **ALB用SG**：インターネット（0.0.0.0/0）から HTTP(80) を受ける
- **EC2用SG**：ALBのSGからの 8080 のみ許可（`referenced_security_group_id`でSG同士を直接参照。IPアドレスではなく「送信元のSG」で制御することで、ALBのIPが変わっても影響を受けない設計）（+ 管理用SSH 22 は管理者IP/32に限定）
- **RDS用SG**：EC2のSGからの 3306 のみ許可（外部からは直接アクセス不可）

DBはプライベートサブネットに配置し、インターネットから隔離しています。

### アプリケーション層（WAF）

ALBの前段にWAFを配置し、AWSマネージドルール **Core rule set（AWSManagedRulesCommonRuleSet）** を適用しています。SQLインジェクション・クロスサイトスクリプティングなど、OWASPで挙げられる一般的な攻撃パターンを検知・ブロックします。

- デフォルトアクションは `allow`（ルールに合致しない通常の通信は許可）
- ルールに合致した通信のみブロック
- 検査結果はCloudWatch Logsに出力し、後から検証可能

### 機密情報の管理

- `my_ip`（管理者IP）、`db_password`（DBパスワード）、`alarm_email`（通知先メールアドレス）は、`variables.tf`にデフォルト値を書かず、`terraform.tfvars`（`.gitignore`で除外）に分離
- `db_password`は`sensitive = true`を設定し、`plan`/`apply`実行時の画面出力でも値が伏せられる（CFn版の`NoEcho`に相当）

---

## 前提条件

- AWSアカウント
- 対象リージョン：**東京（ap-northeast-1）**
- 対象リージョンに、EC2用のキーペアを事前に作成しておくこと
- Terraform v1.0.0以上
- AWS CLIの設定済み認証情報（`aws configure`）

---

## デプロイ手順

### 1. リポジトリをclone

```bash
git clone https://github.com/ogihara-v/aws-study-terraform.git
cd aws-study-terraform
```

### 2. terraform.tfvars を作成

Git管理対象外のため、各自で作成する必要があります。

```hcl
my_ip       = "（自分のグローバルIP）/32"
db_password = "（8文字以上、/ @ \" 半角スペースを含まない値）"
alarm_email = "（通知を受け取りたいメールアドレス）"
```

### 3. 初期化

```bash
terraform init
```

### 4. 実行計画の確認

```bash
terraform plan
```

### 5. 適用

```bash
terraform apply
```

`yes`と入力すると作成が始まります。RDSの作成には5〜15分程度かかるため、**完了まで操作を中断しないでください**（途中で中断すると、リソースが`tainted`（信頼できない状態）と判定され、作り直しが必要になります）。

### 6. SNSの購読確認

作成完了後、`alarm_email`宛てに届く確認メールから **Confirm subscription** をクリックしてください（未承認だと通知が届きません）。

### 7. 出力値の確認

```bash
terraform output
```

- `elb_dns_name`：Webアクセス用のALBのDNS名
- `rds_instance_endpoint`：DB接続用のRDSエンドポイント

---

## 動作確認

### アプリケーション

1. EC2にSSH接続し、Webアプリ（8080で待ち受け）を起動
2. ブラウザで `http://（elb_dns_nameの値）` にアクセス
3. WAF → ALB → EC2 → RDS の経路で、アプリの画面が表示されれば成功

> 注：EC2の8080はALB経由のみ許可のため、EC2のIPへ直接アクセスはできません。必ずALBのDNS名でアクセスします（直接アクセスできないことも、SG設計が正しく機能している証拠として確認済み）。

### 監視アラーム

EC2に負荷をかけ、アラームが発報して通知が届くことを確認します。

```bash
# 負荷をかける（1vCPUを占有）
yes > /dev/null &

# CPU使用率を確認
top -o %CPU

# 負荷を停止
killall yes
```

CloudWatchのアラーム状態が `OK` から `アラーム状態` に変わり、登録したメールアドレスに通知が届くことを確認済みです。評価期間が5分平均のため、発報まで5〜10分程度の余裕を見て負荷をかけ続けます。

### WAFログ

CloudWatch Logs のロググループ `aws-waf-logs-study` に、WAFの検査ログが出力されることを確認済みです。

---

## 後片付け

学習用途のため、確認後は忘れずに削除してください。

```bash
terraform destroy
```

---

## 工夫した点

- **機密情報の秘匿**：DBパスワード・管理者IP・通知先メールアドレスは`terraform.tfvars`に分離し、`.gitignore`で除外。`variables.tf`にはデフォルト値を持たせず、リポジトリ公開時に個人情報が漏れない設計
- **SSHアクセスの限定**：管理用SSHは`0.0.0.0/0`を避け、`my_ip`変数で管理者IP（/32）のみに限定
- **最新AMIの動的取得**：EC2のAMIは`data "aws_ami"`でAmazon Linux 2023の最新版を動的に取得し、AMI IDの直書きを回避
- **RDSバージョンの委譲**：`engine_version`を明示せず、AWSのデフォルトバージョンに委ねることで、バージョン廃止によるデプロイ失敗を回避（CFn版と同じ設計思想）
- **課金事故の再発防止**：開発初期、CFn版でRDSの自動スナップショットが削除後も残存し、想定外の保管料が発生する事象を経験。Terraform版では`skip_final_snapshot = true`を明示し、`destroy`時にスナップショットを残さない設計にすることで再発を防止
- **セキュリティグループ同士の直接参照**：IPアドレスではなく`referenced_security_group_id`でSG同士を紐付けることで、ALBやEC2のIPアドレスが変わっても、通信許可のルールに影響が出ない設計
- **CFn版との対応関係を意識した構成**：`main.tf`内をCFn版と同じ「ネットワーク基盤／セキュリティグループ／アプリ層／ロードバランサー層／データベース層／アラーム通知設定／WAF設定」の順序・区切りコメントで統一し、2つのIaCコードを見比べやすくした

---

## CloudFormation版との構造上の違い（学びのメモ）

同じ構成でも、ツールによって設計思想が異なる点がいくつかありました。

| 項目 | CloudFormation | Terraform |
|---|---|---|
| IGWのVPCアタッチ | `AWS::EC2::VPCGatewayAttachment`という別リソースが必要 | `aws_internet_gateway`の`vpc_id`引数のみで完結 |
| ターゲットグループへのEC2登録 | `ELBTargetGroup`の`Targets`プロパティに埋め込み | `aws_lb_target_group_attachment`という別リソースに分離 |
| SNSサブスクリプション | `AlarmTopic`の`Subscription`プロパティに埋め込み | `aws_sns_topic_subscription`という別リソースに分離 |
| プロパティ名 | `PreferredBackupWindow`等、AWS API層に近い命名 | `backup_window`等、プロバイダー独自の命名（Registry確認が必要） |

---

## 使用技術

Terraform / AWS Provider(~> 5.0) / VPC / EC2 / ALB(ELBv2) / RDS(MySQL) / Security Group / IAM /
SSM Parameter Store / CloudWatch / CloudWatch Logs / SNS / AWS WAF (WAFv2)

---

## 学習の位置づけ

本コードは、AWS設計・構築の学習（ハンズオン）の成果物です。CloudFormationで構築した三層構成をTerraformで再現することで、同じインフラを異なるIaCツールで表現する際の設計思想の違い・構文の違いを実践的に学ぶことを目的としています。
各リソースは、公式ドキュメント（Terraform Registry）を参照しながら、1つずつ`plan`で動作確認しながら積み上げました。

---

## 更新履歴

- ネットワーク基盤（VPC/サブネット/ルートテーブル）を実装
- セキュリティグループ（EC2/RDS/ALB）を実装、多層防御を再現
- EC2・RDS・ALBを実装し、三層構成の疎通を確認
- 監視（CloudWatch Alarm/SNS）を実装、負荷テストによる発報・通知を確認
- WAF（WebACL/ログ出力/ALB関連付け）を実装
- outputsの整備、コードの構造整理（CFn版との対応が分かりやすいセクション分けに統一）

## 提出について
Terraform版の実装完了に伴い、提出用プルリクエストを作成しました。