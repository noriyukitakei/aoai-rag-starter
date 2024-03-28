import os
from azure.search.documents.indexes import SearchIndexClient
from azure.search.documents import SearchClient
from azure.search.documents.indexes.models import *
from langchain.text_splitter import RecursiveCharacterTextSplitter
from azure.ai.formrecognizer import DocumentAnalysisClient
from openai import AzureOpenAI
from azure.search.documents.models import VectorizedQuery
import argparse
import glob
from azure.identity import DefaultAzureCredential, get_bearer_token_provider

# 開発環境・本番環境でも同じ認証方式を使用するため、DefaultAzureCredentialを用いて認証情報を取得する。
azure_credential = DefaultAzureCredential()
token_provider = get_bearer_token_provider(
    DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default"
)

# 環境変数からAzure AI Search、Azure OpenAI、Azure Document Intelligenceのエンドポイントを取得する
search_service_endpoint = os.environ["SEARCH_SERVICE_ENDPOINT"]
aoai_endpoint = os.environ["AOAI_ENDPOINT"]
aoai_api_version = os.environ["AOAI_API_VERSION"]
document_intelligence_endpoint = os.environ["DOCUMENT_INTELLIGENCE_ENDPOINT"]

# Pythonの実行時にコマンドライン引数を受け取るための設定を行う
parser = argparse.ArgumentParser()
parser.add_argument("--docs") # インデックス対象のファイルが格納されているディレクトリを指定する
parser.add_argument("--chunksize", default="1000") # テキストを分割する際のサイズを指定する(デフォルトは1000)
parser.add_argument("--overlap", default="200") # テキストを分割する際のオーバーラップサイズを指定する(デフォルトは200)
parser.add_argument("--remove", action="store_true") # インデックスを削除するかどうかを指定する
args = parser.parse_args()

# テキストを分割する際の区切り文字を指定する
separator = ["\n\n", "\n", "。", "、", " ", ""]

def create_index():
    """
    Azure AI Searchのインデックスを作成する
    """
    client = SearchIndexClient(search_service_endpoint, azure_credential)
    name = "docs"

    # すでにインデックスが作成済みである場合には何もしない
    if 'docs' in client.list_index_names():
        print("すでにインデックスが作成済みです")
        return

    # インデックスのフィールドを定義する
    # id: ドキュメントを一意に識別するためのフィールド
    # content: ドキュメントの内容を格納するためのフィールド
    # contentVector: ドキュメントの内容をベクトル化した結果を格納するためのフィールド
    fields = [
        SimpleField(name="id", type=SearchFieldDataType.String, key=True),
        SearchableField(name="content", type="Edm.String", analyzer_name="ja.microsoft"),
        SearchField(name="contentVector", type=SearchFieldDataType.Collection(SearchFieldDataType.Single),
                searchable=True, vector_search_dimensions=1536, vector_search_profile_name="myHnswProfile")
    ]

    # セマンティック検索のための定義を行う
    semantic_settings = SemanticSearch(
        configurations=[
            SemanticConfiguration(
                name="default",
                prioritized_fields=SemanticPrioritizedFields(
                    title_field=None,
                    content_fields=[
                        SemanticField(field_name="content")
                    ],
                ),
            )
        ]
    )

    # ベクトル検索のための定義を行う
    vector_search = VectorSearch(
        algorithms=[
            HnswAlgorithmConfiguration(
                name="myHnsw"
            )
        ],
        profiles=[
            VectorSearchProfile(
                name="myHnswProfile",
                algorithm_configuration_name="myHnsw",
            )
        ]
    )

    # インデックスを作成する
    index = SearchIndex(name=name, fields=fields, vector_search=vector_search, semantic_search=semantic_settings)
    client.create_index(index)

def delete_index():
    """
    Azure AI Searchのインデックスを削除する
    """
    client = SearchIndexClient(search_service_endpoint, azure_credential)
    client.delete_index('docs')

def index_docs(chunks: list):
    """
    ドキュメントをAzure AI Searchにインデックスする
    """
    # Azure AI SearchのAPIに接続するためのクライアントを生成する
    searchClient = SearchClient(search_service_endpoint, "docs", azure_credential)

    # Azure OpenAIのAPIに接続するためのクライアントを生成する
    openAIClient = AzureOpenAI(azure_endpoint=aoai_endpoint, azure_ad_token_provider=token_provider, api_version = aoai_api_version)


    # chunksというリストに分割したテキストを格納しているので、それぞれのchunkに対してAzure OpenAIのテキスト埋め込みAPIを呼び出し、
    # テキストをベクトル化した結果をAzure AI Searchにアップロードする
    for i, chunk in enumerate(chunks):
        print(f"{i+1}個目のチャンクを処理中...")
        response = openAIClient.embeddings.create(
            input = chunk,
            model = "text-embedding-ada-002-deploy"
        )

        # チャンク化されたテキストとそのテキストのベクトルをAzure AI Searchにアップロードする
        document = {"id": str(i), "content": chunk, "contentVector": response.data[0].embedding}
        searchClient.upload_documents([document])

def create_chunk(content: str, separator: str, chunk_size: int = 512, overlap: int = 0):
    """
    テキストを指定したサイズで分割する
    """
    splitter = RecursiveCharacterTextSplitter(chunk_overlap=overlap, chunk_size=chunk_size, separators=separator)
    chunks = splitter.split_text(content)
    return chunks

def extract_text_from_docs(filepath):
    """
    ドキュメントからテキストを抽出する
    """
    # Azure Document IntelligenceのAPIに接続するためのクライアントを生成する
    form_recognizer_client = DocumentAnalysisClient(endpoint=document_intelligence_endpoint, credential=azure_credential)

    # ドキュメントを読み込んで、Azure Document IntelligenceのAPIを呼び出して、テキストを抽出する
    print(f"{filepath}内のテキストを抽出中...")
    with open(filepath, "rb") as f:
        poller = form_recognizer_client.begin_analyze_document("prebuilt-layout", document = f)
    form_recognizer_results = poller.result()

    # ドキュメントのテキストを抽出する
    # ドキュメントのテキストは、ページごとに分割されているので、それを結合して返す
    text = ""
    for page in form_recognizer_results.pages:
        for line in page.lines:
            text += line.content
    return text

if __name__ == "__main__":
    if args.remove:
        # 引数に--removeが指定されている場合には、インデックスを削除する
        delete_index()
    else:
        # インデックスを作成する
        create_index()

        # 引数--docsで指定されたディレクトリ内のファイルを読み込んで、Azure AI Searchにインデックスする
        for filename in glob.glob(args.docs):
            # ドキュメントからテキストを抽出する
            content = extract_text_from_docs(filename)

            # テキストを指定したサイズで分割する
            chunksize = int(args.chunksize)
            overlap = int(args.overlap)
            result = create_chunk(content, separator, chunksize, overlap)

            # テキストをAzure AI Searchにインデックスする
            index_docs(result)


