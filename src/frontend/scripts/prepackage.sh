#!/bin/bash

# フロントエンドアプリケーションがビルドされる前に実行されるスクリプト

# フロントエンドエンドアプリケーション内に埋め込むバックエンドAPIのエンドポイントを取得し、
# .env.productionファイルに書き出す。この環境変数はビルドされたフロントエンドアプリケーション内で使われる。
azd env get-values 2>/dev/null | grep "^API_ENDPOINT" | sed 's/^API_ENDPOINT="\([^"]*\)"$/VITE_API_ENDPOINT=\1/' > .env.production