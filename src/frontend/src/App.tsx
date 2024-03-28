import { useState, useEffect, useRef } from "react";
import { ChatQuestion } from "./components/ChatQuestion/ChatQuestion";
import { ChatAnswer } from "./components/ChatAnswer/ChatAnswer";
import { ChatAnswerLoading } from "./components/ChatAnswerLoading/ChatAnswerLoading";
import { ChatAnswerError } from "./components/ChatAnswerError/ChatAnswerError";
import { InputQuestion } from "./components/InputQuestion/InputQuestion";


import "./index.css";

function App() {
  const [answers, setAnswers] = useState<{user: string, response: string}[]>([]);

  // 回答一覧の末尾にスクロールするための参照を定義する
  const chatMessageStreamEnd = useRef<HTMLDivElement | null>(null);

  // 回答生成中、つまりAPIからの返答を待っている状態かどうかを示すステートを定義する
  const [isLoading, setIsLoading] = useState<boolean>(false);

  // 最後に送信された質問を保持するための参照を定義する
  const lastQuestionRef = useRef<string>("");

  // エラーが発生したかどうかを示すステートを定義する
  const [isError, setIsError] = useState<boolean>(false);

  // Azure OpenAI Serviceにリクエストを送る関数を定義する
  const makeApiRequest = async (question: string) => {
    // ユーザーからの質問が格納されているquestionを使ってAzure OpenAI Serviceにリクエストを送り、回答を取得する

    // 回答生成中の状態にする。これにより、送信ボタンが無効になる。
    setIsLoading(true);

    // エラーが発生している場合は、エラー状態を解除する
    setIsError(false);

    // 最後に送信された質問を保持する
    lastQuestionRef.current = question;

    // .env.productionにVITE_API_URLが定義されていれば、それを使ってAPIリクエストを送る。
    // 定義されていなければ空白とする。つまり、.env.productionにVITE_API_URLが定義されていない場合は、
    // ローカルの開発環境であると判断し、定義されている場合は本番環境であると判断する。
    const api_host = import.meta.env.VITE_API_ENDPOINT || "";
    const api_url = `${api_host}/api/GenerateAnswerWithAOAI`;

    // answersというステートには、ユーザーからの質問とそれに対する回答が格納されており、画面に表示されている内容を表している。
    // このanswersをAzure OpenAI Serviceに送信するためのリクエスト形式に変換して、historyという変数に格納する。
    const history: {user: string, assistant: string|undefined}[] = answers.map(a => ({ user: a.user, assistant: a.response }));

    // 新しい質問をhistoryに追加する。assistantはまだ回答が生成されていないのでundefinedとする。
    history.push({user: question, assistant: undefined});

    try {
      // Azure OpenAI Serviceにリクエストを送る
      const response = await fetch(api_url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(history)
      });

      // APIからのレスポンスをJSON形式で取得する
      const answer = await response.json();

      // 回答生成中の状態を解除する
      setIsLoading(false);

      // answersステートに新しい質問と回答を追加する。
      setAnswers([...answers, {user: question, response: answer.answer}]);

    } catch (error) {
      // エラーが発生した場合は、エラー状態を設定する
      setIsError(true);

      // 回答生成中の状態を解除する
      setIsLoading(false);
    }

  };

  // ページが読み込まれたときに、チャット画面の末尾にスクロールする
  useEffect(() => chatMessageStreamEnd.current?.scrollIntoView({ behavior: "smooth" }), [isLoading]);

  return (
    <>
      <div className="chat-container">
        <ChatAnswer answer="こんにちは。私はAIアシスタントです。質問をどうぞ。" />
        {answers.map((answer) => (
          <>
            <ChatQuestion question={answer.user} />
            <ChatAnswer answer={answer.response} />
          </>
        ))}
        {isLoading && 
          <>
            <ChatQuestion question={lastQuestionRef.current} />
            <ChatAnswerLoading />
          </>
        }
        {isError && 
          <>
            <ChatQuestion question={lastQuestionRef.current} />
            <ChatAnswerError errorMessage="エラーが発生しました。再度質問してください。" />
          </>
        }
        <div ref={chatMessageStreamEnd} />
      </div>
      <div className="chat-input">
        <InputQuestion onSend={question => makeApiRequest(question)} isLoading={isLoading}/>
      </div>
    </>
  );
}

export default App;
