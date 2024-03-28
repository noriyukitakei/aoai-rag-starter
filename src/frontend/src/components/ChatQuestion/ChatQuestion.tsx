import styles from './ChatQuestion.module.css';

interface Props {
    question: string;
}

export const ChatQuestion = (props: Props) => {
    return (
        <div className={`${styles.chatMessage} ${styles.myMessage}`}>{props.question}</div>
    );
};