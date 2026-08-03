import { createServer } from "node:http";
import { Server } from "socket.io";

const port = Number(process.env.PORT ?? 0);
const path = process.env.SOCKET_IO_PATH ?? "/socket.io/";
const pingInterval = Number(process.env.PING_INTERVAL ?? 250);
const pingTimeout = Number(process.env.PING_TIMEOUT ?? 250);

const httpServer = createServer();
const io = new Server(httpServer, {
  path,
  transports: ["websocket"],
  allowUpgrades: false,
  pingInterval,
  pingTimeout
});

let connectionNumber = 0;
const receivedEvents = [];

io.on("connection", (socket) => {
  connectionNumber += 1;
  socket.emit("fixture:ready", { connectionNumber });

  socket.onAny((name, ...arguments_) => {
    receivedEvents.push({ name, arguments: arguments_ });
  });

  socket.on("fixture:echo", (...arguments_) => {
    socket.emit("fixture:echo", ...arguments_);
  });

  socket.on("fixture:echo-object", (...arguments_) => {
    socket.emit("fixture:echo-object", ...arguments_);
  });

  socket.on("fixture:echo-array", (...arguments_) => {
    socket.emit("fixture:echo-array", ...arguments_);
  });

  socket.on("fixture:multi", (...arguments_) => {
    socket.emit("fixture:multi", ...arguments_);
  });

  socket.on("fixture:emit-shapes", () => {
    socket.emit("fixture:zero");
    socket.emit("fixture:null", null);
    socket.emit("fixture:scalar", 42);
    socket.emit("fixture:object", { value: 1 });
    socket.emit("fixture:array", [1, 2]);
    socket.emit("fixture:multi", 1, "two");
  });

  socket.on("fixture:disconnect-namespace", () => {
    socket.disconnect(true);
  });

  socket.on("fixture:close-transport", () => {
    socket.conn.close();
  });

  socket.on("fixture:delay", (milliseconds, value) => {
    setTimeout(() => socket.emit("fixture:delayed", value), milliseconds);
  });

  socket.on("fixture:emit-acknowledgement", () => {
    socket.emit("fixture:requires-ack", { value: 1 }, () => {});
  });

  socket.on("fixture:received-events", () => {
    socket.emit("fixture:received-events", receivedEvents);
  });
});

httpServer.listen(port, "127.0.0.1", () => {
  const address = httpServer.address();
  process.stdout.write(`RAGNAR_SOCKET_IO_READY ${JSON.stringify({ port: address.port, path })}\n`);
});

function shutdown() {
  io.close(() => {
    httpServer.close(() => process.exit(0));
  });
  setTimeout(() => process.exit(1), 2_000).unref();
}

process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);
