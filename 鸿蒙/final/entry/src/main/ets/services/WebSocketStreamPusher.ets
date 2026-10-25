import webSocket from '@ohos.net.webSocket';
import { BusinessError } from '@kit.BasicServicesKit';

export type WebSocketData = string | ArrayBuffer;

export interface WebSocketStreamPusherOptions {
  url: string;
}

export interface WebSocketStreamPusherEvents {
  onOpen?: () => void;
  onMessage?: (data: string | ArrayBuffer) => void;
  onClose?: (code: number, reason: string) => void;
  onError?: (error: BusinessError) => void;
}

export class WebSocketStreamPusher {
  private ws: webSocket.WebSocket | null = null;
  private connected: boolean = false;
  private options: WebSocketStreamPusherOptions;

  constructor(options: WebSocketStreamPusherOptions) {
    this.options = options;
  }

  isConnected(): boolean {
    return this.connected;
  }

  async connect(events?: WebSocketStreamPusherEvents): Promise<void> {
    await this.disconnect();

    const wsInstance: webSocket.WebSocket = webSocket.createWebSocket();
    this.ws = wsInstance;

    wsInstance.on('open', () => {
      this.connected = true;
      if (events?.onOpen) {
        events.onOpen();
      }
    });

    wsInstance.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
      if (err) {
        if (events?.onError) {
          events.onError(err);
        }
        return;
      }
      if (events?.onMessage) {
        events.onMessage(value);
      }
    });

    wsInstance.on('close', (err: BusinessError, value: webSocket.CloseResult) => {
      this.connected = false;
      if (err) {
        if (events?.onError) {
          events.onError(err);
        }
        return;
      }
      const code: number = value?.code ?? 0;
      const reason: string = value?.reason ?? '';
      if (events?.onClose) {
        events.onClose(code, reason);
      }
    });

    wsInstance.on('error', (err: BusinessError) => {
      this.connected = false;
      if (events?.onError) {
        events.onError(err);
      }
    });

    await new Promise<void>((resolve: () => void, reject: (reason?: Error) => void) => {
      wsInstance.connect(this.options.url, (err: BusinessError, value: boolean) => {
        if (err) {
          if (events?.onError) {
            events.onError(err);
          }
          reject(new Error(`WebSocket connect error: ${err.code} ${err.message}`));
          return;
        }
        if (value) {
          resolve();
          return;
        }
        reject(new Error('WebSocket connect failed'));
      });
    });
  }

  async send(data: WebSocketData): Promise<void> {
    const wsInstance: webSocket.WebSocket | null = this.ws;
    if (!wsInstance || !this.connected) {
      throw new Error('WebSocket not connected');
    }

    await new Promise<void>((resolve: () => void, reject: (reason?: Error) => void) => {
      wsInstance.send(data, (err: BusinessError, value: boolean) => {
        if (err) {
          reject(new Error(`WebSocket send error: ${err.code} ${err.message}`));
          return;
        }
        if (value) {
          resolve();
          return;
        }
        reject(new Error('WebSocket send failed'));
      });
    });
  }

  async disconnect(): Promise<void> {
    const wsInstance: webSocket.WebSocket | null = this.ws;
    this.ws = null;
    this.connected = false;
    if (!wsInstance) {
      return;
    }
    try {
      await new Promise<void>((resolve: () => void) => {
        try {
          wsInstance.close();
        } finally {
          resolve();
        }
      });
    } catch {
    }
  }
}