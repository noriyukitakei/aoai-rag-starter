import os
import azure.functions as func
import json
import logging
from openai import AzureOpenAI
from azure.search.documents import SearchClient
from azure.search.documents.indexes.models import *
from azure.search.documents.models import VectorizedQuery
from azure.core.credentials import AzureKeyCredential
from azure.identity import DefaultAzureCredential, get_bearer_token_provider
import tiktoken
from azure.cosmos import CosmosClient

app = func.FunctionApp()


# 開発環境・本番環境でも同じ認証方式を使用するため、DefaultAzureCredentialを用いて認証情報を取得する。
azure_credential = DefaultAzureCredential()

# 環境変数からAzure AI Servicesのエンドポイントを取得する
search_service_endpoint = os.environ["SEARCH_SERVICE_ENDPOINT"]

token_provider = get_bearer_token_provider(
    DefaultAzureCredential(), "https://cognitiveservices.azure.com/.default"
)

# 環境変数からAzure OpenAIのエンドポイントを取得する
aoai_endpoint = os.environ["AOAI_ENDPOINT"]

# 環境変数からこのチャットで今回利用するモデル名を取得する。
gpt_model = os.environ["AOAI_MODEL"]

# 環境変数からgtp-35-turboのデプロイ名を取得する。
gpt_35_turbo_deploy = os.environ["AOAI_GPT_35_TURBO_DEPLOYMENT"]

# 環境変数からgtp-4のデプロイ名を取得する。
gpt_4_deploy = os.environ["AOAI_GPT_4_DEPLOYMENT"]

# 環境変数からgpt-4-32kのデプロイ名を取得する。
gpt_4_32k_deploy = os.environ["AOAI_GPT_4_32K_DEPLOYMENT"]

# 環境変数からtext-embedding-ada-002のでデプロイ名を取得する。
text_embedding_ada_002_deploy = os.environ["AOAI_TEXT_EMBEDDING_ADA_002_DEPLOYMENT"]

# 環境変数からAzure OpenAI ServiceのAPIのバージョンを取得する。
api_version = os.environ["AOAI_API_VERSION"]

# 環境変数からCosmos DBのエンドポイント、データベース名、コンテナ名を取得する
cosmos_db_endpoint = os.environ["COSMOSDB_ENDPOINT"]
cosmos_db_name = os.environ["COSMOSDB_DATABASE"]
cosmos_db_container_name = os.environ["COSMOSDB_CONTAINER"]

# Azure OpenAI ServiceのAPI接続用クライアントを生成する
openai_client = AzureOpenAI(
    api_version=api_version,
    azure_endpoint=aoai_endpoint,
    azure_ad_token_provider=token_provider,
)

# Azure AI ServicesのAPI接続用クライアントを生成する
search_client = SearchClient(search_service_endpoint, "docs", azure_credential)

# Azure Cosmos DBのAPI接続用クライアントを生成する
database = CosmosClient(cosmos_db_endpoint, azure_credential).get_database_client(cosmos_db_name)
container = database.get_container_client(cosmos_db_container_name)

# AIのキャラクターを決めるためのシステムメッセージを定義する。
system_message_chat_conversation = """
あなたはユーザーの質問に回答するチャットボットです。
回答については、「Sources:」以下に記載されている内容に基づいて回答してください。
回答は簡潔にしてください。
「Sources:」に記載されている情報以外の回答はしないでください。
情報が複数ある場合は「Sources:」のあとに[Source1]、[Source2]、[Source3]のように記載されますので、それに基づいて回答してください。
また、ユーザーの質問に対して、Sources:以下に記載されている内容に基づいて適切な回答ができない場合は、「すみません。わかりません。」と回答してください。
回答の中に情報源の提示は含めないでください。例えば、回答の中に「[Source1]」や「Sources:」という形で情報源を示すことはしないでください。
"""

# ユーザからの質問を元に、Azure AI Searchに投げる検索クエリを生成するためのテンプレートを定義する。
query_prompt_template = """
これまでの会話履歴と、以下のユーザーからの質問に基づいて、検索クエリを生成してください。
回答には検索クエリ以外のものを含めないでください。
例えば、「育児休暇はいつまで取れますか？」という質問があった場合、「育児休暇 取得期間」という形で回答を返してください。

question: {query}
"""

# モデルごとのデプロイ名、最大トークン数、エンコーディングを定義する。
# エンコーディングは、tiktokenライブラリを用いてモデルに応じたエンコーディングを利用して、トークン数を計算するために利用する。
gpt_models = {
    "gpt-35-turbo": {
        "deployment": gpt_35_turbo_deploy,
        "max_tokens": 4096,
        "encoding": tiktoken.encoding_for_model("gpt-3.5-turbo")
    },
    "gpt-4": {
        "deployment": gpt_4_deploy,
        "max_tokens": 8192,
        "encoding": tiktoken.encoding_for_model("gpt-4")
    },
    "gpt-4-32k": {
        "deployment": gpt_4_32k_deploy,
        "max_tokens": 32768,
        "encoding": tiktoken.encoding_for_model("gpt-4-32k")
    },
    "text-embedding-ada-002": {
        "deployment": text_embedding_ada_002_deploy,
        "max_tokens": 4096
    }
}

@app.route(route="GenerateAnswerWithAOAI", auth_level=func.AuthLevel.ANONYMOUS)
def GenerateAnswerWithAOAI(req: func.HttpRequest) -> func.HttpResponse:
    """
    HTTP POSTリクエストを受け取り、Azure OpenAIを用いて回答を生成する。
    """

    logging.info('Python HTTP trigger function processed a request.')

    # POSTリクエストから会話履歴が格納されたJSON配列を取得する。
    history = req.get_json()

    # [{question: "こんにちは。げんきですか？", answer: "元気です。"}, {question: "今日の天気は？", answer: "晴れです。"}...]というJSON配列から
    # 最も末尾に格納されているJSONオブジェクトのquestionを取得する。
    question = history[-1].get('user')

    # Azure AI Seacheにセマンティックハイブリッド検索を行い、回答を生成する。
    answer = semantic_hybrid_search(question, history)

    return func.HttpResponse(
        json.dumps({"answer": answer}),
        mimetype="application/json",
        status_code=200
    )

def semantic_hybrid_search(query: str, history: list[dict]):
    """
    セマンティックサーチとハイブリッドサーチを組み合わせて回答を生成する。
    """

    # 利用するモデルからデプロイ名を取得する。
    gpt_deploy = gpt_models.get(gpt_model).get("deployment")

    # 利用するモデルの最大トークン数を取得する。
    max_tokens = gpt_models.get(gpt_model).get("max_tokens")*0.8 # ギリギリ際を攻めるとエラーが出るため、最大トークン数の80%のトークン数を指定する。

    # Azure OpenAI Serviceの埋め込み用APIを用いて、ユーザーからの質問をベクトル化する。
    # セマンティックハイブリッド検索に必要な「ベクトル化されたクエリ」「キーワード検索用クエリ」のうち、ベクトル化されたクエリを生成する。
    response = openai_client.embeddings.create(
        input = query,
        model = text_embedding_ada_002_deploy
    )
    vector_query = VectorizedQuery(vector=response.data[0].embedding, k_nearest_neighbors=3, fields="contentVector")

    # ユーザーからの質問を元に、Azure AI Searchに投げる検索クエリを生成する。
    # セマンティックハイブリッド検索に必要な「ベクトル化されたクエリ」「キーワード検索用クエリ」のうち、検索クエリを生成する。
    messages_for_search_query = []

    # 会話履歴の最後に、キーワード検索用クエリを生成するためのプロンプトを追加する。
    for h in history[:-1]:
        messages_for_search_query.append({"role": "user", "content": h["user"]})
        messages_for_search_query.append({"role": "assistant", "content": h["assistant"]})
    messages_for_search_query.append({"role": "user", "content": query_prompt_template.format(query=query)})

    messages_for_search_query = trim_messages(messages_for_search_query, max_tokens)

    response = openai_client.chat.completions.create(
        model=gpt_deploy,
        messages=messages_for_search_query
    )
    search_query = response.choices[0].message.content

    # 「ベクトル化されたクエリ」「キーワード検索用クエリ」を用いて、Azure AI Searchに対してセマンティックハイブリッド検索を行う。
    results = search_client.search(query_type='semantic', semantic_configuration_name='default',
        search_text=search_query, 
        vector_queries=[vector_query],
        select=['id', 'content'], query_caption='extractive', query_answer="extractive", highlight_pre_tag='<em>', highlight_post_tag='</em>', top=2)

    # セマンティックアンサーを取得する。
    semantic_answers = results.get_answers()

    messages_for_semantic_answer = []

    messages_for_semantic_answer.append({"role": "system", "content": system_message_chat_conversation})

    # Azure OpenAI Serviceに回答を生成する際の会話履歴を生成する。まずは画面から渡された会話履歴を
    # Azure OpenAI Seriviceに渡す形式({"role": "XXX", "content": "XXX"})に変換する。
    for h in history[:-1]:
        messages_for_semantic_answer.append({"role": "user", "content": h["user"]})
        messages_for_semantic_answer.append({"role": "assistant", "content": h["assistant"]})

    # セマンティックアンサーの有無で返答を変える
    user_message = ""
    if len(semantic_answers) == 0:
        # Azure AI Searchがセマンティックアンサーを返さなかった場合は、
        # topで指定された複数のドキュメントを回答生成のための情報源として利用する。
        sources = ["[Source" + result["id"] + "]: " + result["content"] for result in results]
        source = "\n".join(sources)

        user_message = """
        {query}

        Sources:
        {source}
        """.format(query=query, source=source)
    else:
        # Azure AI Searchがセマンティックアンサーを返した場合は、それを回答生成のための情報源として利用する。
        user_message = """
        {query}

        Sources:
        {source}
        """.format(query=query, source=semantic_answers[0].text)

    messages_for_semantic_answer.append({"role": "user", "content": user_message})

    # Azure OpenAI ServiceのAPIの仕様で定められたトークン数の制限に基づき、
    # 指定されたトークン数に従って、会話履歴を古い順から削除する。
    messages_for_semantic_answer = trim_messages(messages_for_semantic_answer, max_tokens)

    # Azure OpenAI Serviceに回答生成を依頼する。
    response = openai_client.chat.completions.create(
        model=gpt_deploy,
        messages=messages_for_semantic_answer
    )
    response_text = response.choices[0].message.content

    # チャットログをCosmos DBに書き込む。
    write_chatlog("guest", query, response_text)

    return response_text

def trim_messages(messages, max_tokens):
    """
    会話履歴の合計のトークン数が最大トークン数を超えないように、古いメッセージから削除する。
    """

    # 利用するモデルからエンコーディングを取得する。
    encoding = gpt_models.get(gpt_model).get("encoding")

    # 各メッセージのトークン数を計算
    token_counts = [(message, len(encoding.encode(message["content"]))) for message in messages]
    total_tokens = sum(count for _, count in token_counts)

    # トークン数が最大トークン数を超えないように、古いメッセージから削除する
    # もし最大トークン数を超える場合は、systemメッセージ以外のメッセージを古い順から削除する。
    # この処理をトークン数が最大トークン数を下回るまで行う。
    while total_tokens > max_tokens:  
        messages.pop(1)
        total_tokens -= token_counts.pop(1)[1]
        if total_tokens <= max_tokens:
            break
    
    return messages

def write_chatlog(user_name: str, input: str, response: str):
    """
    チャットログをCosmos DBに書き込む。
    """
    properties = {
        "user" : user_name, 
        "input" : input,  
        "response" : response
    }

    container.create_item(body=properties, enable_automatic_id_generation=True)