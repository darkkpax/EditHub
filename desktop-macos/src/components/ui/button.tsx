import * as React from "react";
import { motion } from "motion/react";
import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import { cn } from "../../lib";
const variants = cva("button", {
  variants: {
    variant: {
      default: "button-primary",
      outline: "button-outline",
      ghost: "button-ghost",
      destructive: "button-danger",
    },
    size: { default: "", sm: "button-sm", icon: "button-icon" },
  },
  defaultVariants: { variant: "default", size: "default" },
});
export interface ButtonProps
  extends
    Omit<
      React.ButtonHTMLAttributes<HTMLButtonElement>,
      "onDrag" | "onDragStart" | "onDragEnd" | "onAnimationStart"
    >,
    VariantProps<typeof variants> {
  asChild?: boolean;
}
export const Button = React.forwardRef<HTMLButtonElement, ButtonProps>(
  ({ className, variant, size, asChild = false, ...props }, ref) => {
    const Comp = asChild ? Slot : motion.button;
    return (
      <Comp
        {...(!asChild && !props.disabled
          ? { whileHover: { y: -2 }, whileTap: { scale: 0.96 } }
          : {})}
        ref={ref}
        className={cn(variants({ variant, size }), className)}
        {...props}
      />
    );
  },
);
Button.displayName = "Button";
