export interface PluginInterface {
  initialize(): Promise<boolean>;
  shutdown(): Promise<void>;
  getName(): string;
  getVersion(): string;
  isInitialized(): boolean;
} 