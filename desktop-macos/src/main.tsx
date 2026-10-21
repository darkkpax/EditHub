import React from "react";
import ReactDOM from "react-dom/client";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { MotionConfig } from "motion/react";
import App from "./App";
import { readTheme } from "./theme";
import "./styles.css";
document.documentElement.dataset.theme = readTheme();
const client = new QueryClient({
  defaultOptions: { queries: { retry: 1, refetchOnWindowFocus: true } },
});
ReactDOM.createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <QueryClientProvider client={client}>
      <MotionConfig
        reducedMotion="user"
        transition={{ type: "spring", stiffness: 340, damping: 30, mass: 0.8 }}
      >
        <App />
      </MotionConfig>
    </QueryClientProvider>
  </React.StrictMode>,
);
