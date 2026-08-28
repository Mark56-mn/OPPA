import express from "express";
import helmet from "helmet";

const app = express();
const port = Number(process.env.PORT ?? 8080);

app.disable("x-powered-by");
app.use(helmet());
app.use(express.json({ limit: "32kb" }));

app.get("/health", (_req, res) => {
  res.status(200).json({
    ok: true,
    service: "oppa-api",
    timestamp: new Date().toISOString()
  });
});

app.get("/readiness", (_req, res) => {
  res.status(200).json({
    ready: true,
    service: "oppa-api"
  });
});

app.use((_req, res) => {
  res.status(404).json({ error: "NOT_FOUND" });
});

app.listen(port, () => {
  console.log(`OPPA API listening on port ${port}`);
});
