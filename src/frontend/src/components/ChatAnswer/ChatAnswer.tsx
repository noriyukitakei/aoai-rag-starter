import styles from './ChatAnswer.module.css';

interface Props {
    answer: string|undefined;
}

export const ChatAnswer = (props: Props) => {
    return (
        <div className={`${styles.chatMessage} ${styles.otherMessage}`}>{props.answer}</div>
    );
};