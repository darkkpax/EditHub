import * as DialogPrimitive from "@radix-ui/react-dialog";
import { motion } from "motion/react";
import { X } from "lucide-react";
import type { ReactNode } from "react";
export const Dialog = DialogPrimitive.Root;
export const DialogTrigger = DialogPrimitive.Trigger;
export function DialogContent({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children: ReactNode;
}) {
  return (
    <DialogPrimitive.Portal>
      <DialogPrimitive.Overlay className="dialog-overlay" />
      <div className="dialog-position">
        <DialogPrimitive.Content
          asChild
          aria-describedby={description ? "dialog-description" : undefined}
        >
          <motion.div
            className="dialog-content"
            initial={{ opacity: 0, scale: 0.94, y: 16 }}
            animate={{ opacity: 1, scale: 1, y: 0 }}
          >
            <div className="dialog-heading">
              <div>
                <DialogPrimitive.Title className="dialog-display">
                  {title}
                </DialogPrimitive.Title>
              </div>
              <DialogPrimitive.Close className="icon-button" aria-label="Close">
                <X size={18} />
              </DialogPrimitive.Close>
            </div>
            {description && (
              <DialogPrimitive.Description id="dialog-description">
                {description}
              </DialogPrimitive.Description>
            )}
            {children}
          </motion.div>
        </DialogPrimitive.Content>
      </div>
    </DialogPrimitive.Portal>
  );
}
