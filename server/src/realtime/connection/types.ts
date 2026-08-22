import { WebSocket } from 'ws';

export interface AuthenticatedSocketData {
  userId: number;
  email: string;
}

export interface RealtimeClient {
  socket: WebSocket;
  auth: AuthenticatedSocketData;
}
