import { useState } from "react";
import styles from './InputQuestion.module.css';

interface Props {
    onSend: (question: string) => void;
    isLoading: boolean;
}

export const InputQuestion = ({ onSend, isLoading }: Props) => {
    const [question, setQuestion] = useState<string>("");

    // 漢字変換候補決定の際のEnterキーを押下しても質問が送信されないようにするためのステートを定義する
    const [composing, setComposition] = useState<boolean>(false);
    const startComposition = () => setComposition(true);
    const endComposition = () => setComposition(false);

    // 質問を送信する関数を定義する
    const sendQuestion = () => {
        // 質問が空白の場合は何もしない
        if (!question.trim()) {
            return;
        }

        // 質問を送信する
        onSend(question);

        // 質問を空白にする
        setQuestion("");
    };

    // Enterキーが押されたときに質問を送信する
    const onEnterPress = (ev: React.KeyboardEvent<Element>) => {
        // 回答が生成中の場合は何もしない
        if (isLoading || composing) {
            return;
        }


        // Enterキーが押されたかつShiftキーが押されていない場合
        if (ev.key === "Enter" && !ev.shiftKey) {
            ev.preventDefault();
            sendQuestion();
        }
    };

    return (
        <>
            <input
                type="text"
                placeholder="質問を入力してください"
                value={question}
                onChange={(e) => setQuestion(e.target.value)}
                onKeyDown={onEnterPress}
                onCompositionStart={startComposition}
                onCompositionEnd={endComposition}
            />
            <button
                className={ isLoading ? `${styles.button_disabled}` : `${styles.button}` }
                onClick={sendQuestion}
                disabled={isLoading} >送信</button>
        </>
        
    );

}