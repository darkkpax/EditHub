import { motion, useReducedMotion } from "motion/react";

export function FrostedSelection({
  id,
  className,
}: {
  id: string;
  className: string;
}) {
  const reduced = useReducedMotion();
  return (
    <motion.i
      aria-hidden="true"
      layoutId={id}
      className={className}
      transition={{
        layout: {
          type: "tween",
          duration: reduced ? 0 : 0.32,
          ease: [0.22, 1, 0.36, 1],
        },
      }}
    />
  );
}
