import styles from './ChatAnswerLoading.module.css';
import { useSpring, animated } from '@react-spring/web';
import { useState } from 'react';

export const ChatAnswerLoading = () => {
    const [dots, setDots] = useState('.');
    const stylesa = useSpring({
      from: { opacity: 0 },
      to: { opacity: 1 },
      reset: true,
      reverse: dots.length === 3,
      delay: 200,
      onRest: () => setDots(dots => dots.length < 3 ? dots + '.' : '.'),
    });

    return (
        <div className={`${styles.chatMessage} ${styles.otherMessage}`}>
            回答を生成中です🖊
            <animated.span style={stylesa}>{dots}</animated.span>
        </div>
    );
};