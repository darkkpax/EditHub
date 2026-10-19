import { useEffect, useRef, useState, type ReactNode } from "react";

export function ScrollGlass({
  children,
  className,
  resetKey,
}: {
  children: ReactNode;
  className: string;
  resetKey?: string;
}) {
  const viewport = useRef<HTMLDivElement>(null);
  const content = useRef<HTMLDivElement>(null);
  const [edges, setEdges] = useState({ top: false, bottom: false });
  const update = () => {
    const el = viewport.current;
    if (!el) return;
    const header = content.current?.firstElementChild;
    const inset =
      header instanceof HTMLElement &&
      header.matches(".sidebar-controls,.project-hero")
        ? header.offsetHeight + 12
        : 12;
    el.style.scrollPaddingTop = `${inset}px`;
    const footer = content.current?.lastElementChild;
    el.style.scrollPaddingBottom = `${footer instanceof HTMLElement && footer.classList.contains("sidebar-bottom") ? footer.offsetHeight + 12 : 60}px`;
    const next = {
      top: el.scrollTop > 2,
      bottom: el.scrollHeight - el.clientHeight - el.scrollTop > 2,
    };
    setEdges((old) =>
      old.top === next.top && old.bottom === next.bottom ? old : next,
    );
  };
  useEffect(() => {
    if (viewport.current) viewport.current.scrollTop = 0;
  }, [resetKey]);
  useEffect(() => {
    update();
    const observer = new ResizeObserver(update);
    if (viewport.current) observer.observe(viewport.current);
    if (content.current) observer.observe(content.current);
    return () => observer.disconnect();
  }, [children]);
  return (
    <div className={`scroll-frame ${className}`}>
      <div
        ref={viewport}
        className="scroll-viewport"
        onScroll={update}
        tabIndex={0}
        role="region"
        aria-label={
          className === "project-list" ? "Project list" : "Project files"
        }
      >
        <div ref={content} className="scroll-content">
          {children}
        </div>
      </div>
      <div
        aria-hidden="true"
        className="scroll-edge scroll-edge-top"
        style={{ opacity: edges.top ? 1 : 0 }}
      />
      <div
        aria-hidden="true"
        className="scroll-edge scroll-edge-bottom"
        style={{ opacity: edges.bottom ? 1 : 0 }}
      />
    </div>
  );
}
