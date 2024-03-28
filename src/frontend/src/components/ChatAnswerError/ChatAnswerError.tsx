import styles from './ChatAnswerError.module.css';

interface Props {
    errorMessage: string|undefined;
}

export const ChatAnswerError = (props: Props) => {
    return (
        <div className={`${styles.chatMessage} ${styles.otherMessage}`}>{props.errorMessage}</div>
    );
};